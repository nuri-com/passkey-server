const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function initDatabase() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        user_id BYTEA NOT NULL,
        email VARCHAR(255),
        encrypted_data JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS authenticators (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        credential_id BYTEA NOT NULL,
        credential_public_key BYTEA NOT NULL,
        counter INTEGER NOT NULL,
        credential_device_type VARCHAR(50),
        credential_backed_up BOOLEAN,
        transports TEXT[],
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(credential_id)
      )
    `);

    // Create activity log table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS activity_logs (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
        username VARCHAR(255),
        action VARCHAR(50) NOT NULL,
        status VARCHAR(20) NOT NULL,
        credential_id VARCHAR(255),
        ip_address VARCHAR(45),
        user_agent TEXT,
        error_message TEXT,
        metadata JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Create index for faster queries
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at 
      ON activity_logs(created_at DESC)
    `);
    
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_activity_logs_user_id 
      ON activity_logs(user_id)
    `);

    console.log('Database initialized successfully');
  } catch (error) {
    console.error('Error initializing database:', error);
    throw error;
  }
}

async function createUser(username, userId) {
  const result = await pool.query(
    'INSERT INTO users (username, user_id) VALUES ($1, $2) RETURNING *',
    [username, userId]
  );
  return result.rows[0];
}

async function createAnonymousUser(credentialId) {
  // Use credential ID as the username for anonymous users
  const username = `anon_${Buffer.from(credentialId).toString('base64url').substring(0, 16)}`;
  const result = await pool.query(
    'INSERT INTO users (username, user_id) VALUES ($1, $2) RETURNING *',
    [username, credentialId]
  );
  return result.rows[0];
}

async function getUserByUsername(username) {
  const result = await pool.query(
    'SELECT * FROM users WHERE username = $1',
    [username]
  );
  return result.rows[0];
}

async function getUserById(userId) {
  const result = await pool.query(
    'SELECT * FROM users WHERE id = $1',
    [userId]
  );
  return result.rows[0];
}

async function saveAuthenticator(userId, authenticator) {
  const result = await pool.query(
    `INSERT INTO authenticators 
     (user_id, credential_id, credential_public_key, counter, 
      credential_device_type, credential_backed_up, transports)
     VALUES ($1, $2, $3, $4, $5, $6, $7) 
     RETURNING *`,
    [
      userId,
      authenticator.credentialID,
      authenticator.credentialPublicKey,
      authenticator.counter,
      authenticator.credentialDeviceType,
      authenticator.credentialBackedUp,
      authenticator.transports || []
    ]
  );
  return result.rows[0];
}

async function getAuthenticatorsByUserId(userId) {
  const result = await pool.query(
    'SELECT * FROM authenticators WHERE user_id = $1',
    [userId]
  );
  return result.rows.map(row => ({
    credentialID: row.credential_id,
    credentialPublicKey: row.credential_public_key,
    counter: row.counter,
    credentialDeviceType: row.credential_device_type,
    credentialBackedUp: row.credential_backed_up,
    transports: row.transports
  }));
}

async function getAuthenticatorById(credentialId) {
  const result = await pool.query(
    'SELECT * FROM authenticators WHERE credential_id = $1',
    [credentialId]
  );
  
  if (result.rows.length === 0) return null;
  
  const row = result.rows[0];
  return {
    credentialID: row.credential_id,
    credentialPublicKey: row.credential_public_key,
    counter: row.counter || 0,
    credentialDeviceType: row.credential_device_type,
    credentialBackedUp: row.credential_backed_up,
    transports: row.transports || [],
    userId: row.user_id
  };
}

async function updateAuthenticatorCounter(credentialId, counter) {
  await pool.query(
    'UPDATE authenticators SET counter = $1 WHERE credential_id = $2',
    [counter, credentialId]
  );
}

async function updateUserData(userId, data) {
  const { email, encryptedData } = data;
  const result = await pool.query(
    `UPDATE users 
     SET email = COALESCE($2, email), 
         encrypted_data = COALESCE($3, encrypted_data),
         updated_at = CURRENT_TIMESTAMP
     WHERE id = $1 
     RETURNING *`,
    [userId, email, encryptedData]
  );
  return result.rows[0];
}

async function getUserDataByUsername(username) {
  const result = await pool.query(
    `SELECT id, username, email, encrypted_data, created_at, updated_at 
     FROM users 
     WHERE username = $1`,
    [username]
  );
  return result.rows[0];
}

async function getUserByCredentialId(credentialId) {
  const result = await pool.query(
    `SELECT u.* FROM users u 
     JOIN authenticators a ON u.id = a.user_id 
     WHERE a.credential_id = $1`,
    [credentialId]
  );
  return result.rows[0];
}

// Activity logging functions
async function logActivity(data) {
  const {
    userId,
    username,
    action,
    status,
    credentialId,
    ipAddress,
    userAgent,
    errorMessage,
    metadata
  } = data;

  const result = await pool.query(
    `INSERT INTO activity_logs 
     (user_id, username, action, status, credential_id, ip_address, user_agent, error_message, metadata)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) 
     RETURNING *`,
    [userId, username, action, status, credentialId, ipAddress, userAgent, errorMessage, metadata]
  );
  return result.rows[0];
}

async function getActivityLogs(options = {}) {
  const { limit = 100, offset = 0, userId, action, status } = options;
  
  let query = `
    SELECT 
      al.*,
      u.username as user_username,
      a.credential_device_type,
      a.credential_backed_up
    FROM activity_logs al
    LEFT JOIN users u ON al.user_id = u.id
    LEFT JOIN authenticators a ON al.credential_id = a.credential_id::text
    WHERE 1=1
  `;
  
  const params = [];
  let paramCount = 0;
  
  if (userId) {
    params.push(userId);
    query += ` AND al.user_id = $${++paramCount}`;
  }
  
  if (action) {
    params.push(action);
    query += ` AND al.action = $${++paramCount}`;
  }
  
  if (status) {
    params.push(status);
    query += ` AND al.status = $${++paramCount}`;
  }
  
  query += ` ORDER BY al.created_at DESC`;
  
  params.push(limit);
  query += ` LIMIT $${++paramCount}`;
  
  params.push(offset);
  query += ` OFFSET $${++paramCount}`;
  
  const result = await pool.query(query, params);
  
  // Get total count
  let countQuery = `SELECT COUNT(*) FROM activity_logs al WHERE 1=1`;
  const countParams = [];
  paramCount = 0;
  
  if (userId) {
    countParams.push(userId);
    countQuery += ` AND al.user_id = $${++paramCount}`;
  }
  
  if (action) {
    countParams.push(action);
    countQuery += ` AND al.action = $${++paramCount}`;
  }
  
  if (status) {
    countParams.push(status);
    countQuery += ` AND al.status = $${++paramCount}`;
  }
  
  const countResult = await pool.query(countQuery, countParams);
  
  return {
    logs: result.rows,
    total: parseInt(countResult.rows[0].count),
    limit,
    offset
  };
}

async function getActivityStats() {
  const result = await pool.query(`
    SELECT 
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as last_24h,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as last_7d,
      COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days') as last_30d,
      COUNT(*) FILTER (WHERE action = 'registration' AND status = 'success') as total_registrations,
      COUNT(*) FILTER (WHERE action = 'authentication' AND status = 'success') as total_authentications,
      COUNT(*) FILTER (WHERE status = 'error') as total_errors,
      COUNT(DISTINCT user_id) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as active_users_24h
    FROM activity_logs
  `);
  
  return result.rows[0];
}

module.exports = {
  pool,
  initDatabase,
  createUser,
  createAnonymousUser,
  getUserByUsername,
  getUserById,
  getUserByCredentialId,
  saveAuthenticator,
  getAuthenticatorsByUserId,
  getAuthenticatorById,
  updateAuthenticatorCounter,
  updateUserData,
  getUserDataByUsername,
  logActivity,
  getActivityLogs,
  getActivityStats
};