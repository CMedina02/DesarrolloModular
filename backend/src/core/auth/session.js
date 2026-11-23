import { sendError } from "../http/errors.js";

export function unauthorized(response) {
  return sendError(response, 401, "UNAUTHENTICATED", "Credenciales o sesión no válidas.");
}

export function forbidden(response) {
  return sendError(response, 403, "FORBIDDEN", "La operación no está disponible para la sesión actual.");
}

export function createRequireSession({ users, tokens }) {
  return async function requireSession(request, response, next) {
    response.set("Cache-Control", "no-store");
    const authorization = request.get("authorization") ?? "";
    const token = /^Bearer +([A-Za-z0-9_.-]+)$/i.exec(authorization)?.[1];
    const id = token ? await tokens.verify(token) : null;
    const user = id ? await users.findById(id) : null;

    if (!user) {
      response.set("WWW-Authenticate", "Bearer");
      return unauthorized(response);
    }

    request.authUser = user;
    return next();
  };
}

export function requireRoles(...roles) {
  return (request, response, next) => {
    if (!roles.includes(request.authUser.role)) {
      return forbidden(response);
    }

    return next();
  };
}
