export function sendError(response, status, code, message) {
  return response.status(status).json({ error: { code, message } });
}
