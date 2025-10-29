# Toggl to Netvisor Time Reporter

A web application to fetch Toggl time entries and convert them to Netvisor-compatible format with automatic rounding and lunch deductions.

> **Note:** This project also includes `toggl-to-netvisor.sh` - a bash script version that provides the same functionality via command line interface.

## Features

- 🔐 Secure API proxy with CSRF protection
- 💾 Client-side caching with localStorage
- ⚙️ Configurable round-down threshold (0/5/10/15 minutes)
- 📊 Weekly time reports with 15-minute rounding
- 🎨 Modern, responsive dark mode UI
- 🔔 Toast notifications system
- 🐳 Docker support

## Quick Start

### Using Pre-built Docker Image (Easiest)

```bash
# Pull and run the pre-built image
docker run -d -p 80:80 racle90/toggl-to-netvisor:latest

# Or with docker-compose, use:
# image: racle90/toggl-to-netvisor:latest
```

Pre-built images are available at: https://hub.docker.com/repository/docker/racle90/toggl-to-netvisor

### Using Docker Compose (Recommended)

```bash
docker-compose up -d
```

The application will be available at `http://localhost:80`

### Using Docker (Build from Source)

```bash
# Build the image
docker build -t toggl-to-netvisor .

# Run the container
docker run -d -p 80:80 toggl-to-netvisor
```

### Manual Installation

```bash
# Install dependencies
npm install

# Start the server
npm start
```

## Configuration

1. Open the application in your browser
2. Enter your Toggl API token
   - Get your API token from: https://track.toggl.com/profile#api-token
3. Configure the number of past weeks to display (1-8 weeks)
4. Set the round-down threshold for time rounding (0-15 minutes)
5. Click "Get New Data" to fetch your time entries

### Running on a Subdirectory

To run the application on a subdirectory (e.g., `/toggl-to-netvisor`), set the `BASE_PATH` environment variable:

```bash
# With Docker Compose - edit docker-compose.yml
environment:
  - BASE_PATH=/toggl-to-netvisor

# Or with Docker
docker run -d -p 80:80 -e BASE_PATH=/toggl-to-netvisor toggl-to-netvisor

# Or manually
BASE_PATH=/toggl-to-netvisor node src/server.js
```

Then access the app at `http://localhost/toggl-to-netvisor`

## How It Works

### Time Calculation

1. **Raw Time**: Total seconds tracked in Toggl
2. **Rounding**: Time is rounded to the nearest 15-minute block based on threshold
   - If minutes over the last 15-min block < threshold: round down
   - Otherwise: round up
3. **Netvisor Time**: Rounded time minus 30 minutes (lunch break)

### CSRF Protection

- Server generates unique CSRF tokens for each session
- Tokens expire after 1 hour of inactivity
- All API requests require valid CSRF token

### Caching

- Time entries are cached in localStorage
- No API calls needed when refreshing the page
- Use "Clear Cache" to force fresh data fetch

## API Endpoints

- `GET /` - Serve the web application
- `GET /api/csrf-token` - Get a CSRF token
- `POST /api/toggl/time-entries` - Proxy to Toggl API (requires CSRF token)
- `GET /health` - Health check endpoint

## Environment

- Node.js 22+
- Port 80 (configurable)

## Security Notes

- Never expose your Toggl API token
- CSRF tokens are required for all API calls
- API token is stored in localStorage (encrypted password input)
- Backend proxy prevents CORS issues

## Development

```bash
# Install dependencies
npm install

# Run in development mode
node src/server.js
```

## Alternative: Command Line Script

For users who prefer command line interface, use `scripts/toggl-to-netvisor.sh`:

```bash
# Get your API token from: https://track.toggl.com/profile#api-token

# Option 1: Set your API token as environment variable
export TOGGL_API_TOKEN="your_token_here"

# Option 2: Run without setting token (script will prompt for it)
./scripts/toggl-to-netvisor.sh

# Run for last week + current week (default)
./scripts/toggl-to-netvisor.sh

# Run for last 4 weeks + current week
./scripts/toggl-to-netvisor.sh 4
```

The bash script provides the same time calculation and Netvisor formatting without needing a web server. If `TOGGL_API_TOKEN` is not exported, the script will securely prompt you to enter it.

## License

MIT License - This project is free and open-source software. You are free to:

- ✅ Use commercially
- ✅ Modify and distribute
- ✅ Use privately
- ✅ Sublicense

The only requirement is to include the original copyright notice and license text in any copies or substantial portions of the software. The software is provided "as is" without warranty of any kind.
