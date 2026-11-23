export function sendError(response, status, code, message) {
  return response.status(status).json({ error: { code, message } });
}

export function notFound(response) {
  return sendError(response, 404, "NOT_FOUND", "No se encontró el recurso.");
}
