const express = require('express')
const cors = require('cors')
const crypto = require('crypto')
const path = require('path')
const fs = require('fs')

const app = express()
const PORT = 80
const BASE_PATH = process.env.BASE_PATH || ''

// CSRF token storage (in production, use Redis or similar)
const csrfTokens = new Map()

// Middleware
app.use(cors())
app.use(express.json())

// Serve favicon with cache headers
app.get(`${BASE_PATH}/t2n-favicon.png`, (req, res) => {
  res.setHeader('Cache-Control', 'public, max-age=31536000, immutable') // 1 year
  res.sendFile(path.join(__dirname, 't2n-favicon.png'))
})

// Serve GitHub icon with cache headers
app.get(`${BASE_PATH}/github.png`, (req, res) => {
  res.setHeader('Cache-Control', 'public, max-age=31536000, immutable') // 1 year
  res.sendFile(path.join(__dirname, 'github.png'))
})

// Serve index.html with BASE_PATH injection and cache headers
app.get(`${BASE_PATH}/`, (req, res) => {
  const htmlPath = path.join(__dirname, 'index.html')
  fs.readFile(htmlPath, 'utf8', (err, data) => {
    if (err) {
      return res.status(500).send('Error loading page')
    }
    const injected = data.replace(/\{\{BASE_PATH\}\}/g, BASE_PATH)
    res.setHeader('Cache-Control', 'public, max-age=604800') // 1 week
    res.type('html').send(injected)
  })
})

// Generate CSRF token
app.get(`${BASE_PATH}/api/csrf-token`, (req, res) => {
  const token = crypto.randomBytes(32).toString('hex')
  const sessionId = crypto.randomBytes(16).toString('hex')

  csrfTokens.set(sessionId, {
    token,
    timestamp: Date.now(),
  })

  // Clean up old tokens (older than 1 hour)
  const oneHourAgo = Date.now() - 3600000
  for (const [key, value] of csrfTokens.entries()) {
    if (value.timestamp < oneHourAgo) {
      csrfTokens.delete(key)
    }
  }

  res.json({ token, sessionId })
})

// Verify CSRF token middleware
function verifyCsrfToken(req, res, next) {
  const token = req.headers['x-csrf-token']
  const sessionId = req.headers['x-session-id']

  if (!token || !sessionId) {
    return res.status(403).json({ error: 'CSRF token missing' })
  }

  const stored = csrfTokens.get(sessionId)
  if (!stored || stored.token !== token) {
    return res.status(403).json({ error: 'Invalid CSRF token' })
  }

  // Token is valid for 1 hour
  if (Date.now() - stored.timestamp > 3600000) {
    csrfTokens.delete(sessionId)
    return res.status(403).json({ error: 'CSRF token expired' })
  }

  next()
}

// Proxy endpoint for Toggl API
app.post(`${BASE_PATH}/api/toggl/time-entries`, verifyCsrfToken, async (req, res) => {
  const { apiToken, startDate, endDate } = req.body

  if (!apiToken || !startDate || !endDate) {
    return res.status(400).json({ error: 'Missing required parameters' })
  }

  try {
    const url = `https://api.track.toggl.com/api/v9/me/time_entries?start_date=${encodeURIComponent(startDate)}&end_date=${encodeURIComponent(endDate)}`

    const response = await fetch(url, {
      headers: {
        Authorization: 'Basic ' + Buffer.from(apiToken + ':api_token').toString('base64'),
        'Content-Type': 'application/json',
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error('Toggl API Error:', response.status, errorText)
      return res.status(response.status).json({
        error: `Toggl API Error: ${response.status} ${response.statusText}`,
        details: errorText,
      })
    }

    const data = await response.json()
    res.json(data)
  } catch (error) {
    console.error('Error fetching from Toggl:', error)
    res.status(500).json({
      error: 'Failed to fetch data from Toggl',
      details: error.message,
    })
  }
})

// Health check endpoint
app.get(`${BASE_PATH}/health`, (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), basePath: BASE_PATH || '/' })
})

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on http://0.0.0.0:${PORT}${BASE_PATH}`)
  console.log(`CSRF tokens will expire after 1 hour of inactivity`)
})
