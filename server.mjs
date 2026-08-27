import { createServer } from 'node:http'
import { createReadStream, existsSync, statSync } from 'node:fs'
import { join, normalize, extname, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = fileURLToPath(new URL('.', import.meta.url))
const publicRoot = join(projectRoot, 'public')
const publicPrefix = publicRoot.endsWith(sep) ? publicRoot : `${publicRoot}${sep}`
const port = Number(process.env.PORT || 3000)
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
}
const securityHeaders = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'X-Frame-Options': 'SAMEORIGIN',
}

function send(response, status, body, method = 'GET') {
  response.writeHead(status, {
    ...securityHeaders,
    'Content-Type': 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store',
  })
  response.end(method === 'HEAD' ? undefined : body)
}

export const server = createServer((request, response) => {
  const method = request.method || 'GET'
  if (method !== 'GET' && method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD')
    send(response, 405, 'Method not allowed', method)
    return
  }

  let pathname
  try {
    pathname = decodeURIComponent(
      new URL(request.url || '/', `http://${request.headers.host || 'localhost'}`).pathname,
    )
  } catch {
    send(response, 400, 'Bad request', method)
    return
  }

  const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '')
  const file = normalize(join(publicRoot, relative))

  // Runtime and Vercel now serve the same canonical public/ files. The old
  // /js special case silently served root/js locally but public/js in prod.
  if (!file.startsWith(publicPrefix) || !existsSync(file) || !statSync(file).isFile()) {
    send(response, 404, 'Not found', method)
    return
  }

  response.writeHead(200, {
    ...securityHeaders,
    'Content-Type': types[extname(file).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': 'no-cache',
  })
  if (method === 'HEAD') {
    response.end()
    return
  }
  createReadStream(file).on('error', () => {
    if (!response.headersSent) send(response, 500, 'Internal server error', method)
    else response.destroy()
  }).pipe(response)
})

if (process.env.NODE_ENV !== 'test') {
  server.listen(port, '0.0.0.0', () => {
    console.log(`[PlayPro] Static preview server listening on port ${port}`)
  })
}
