import { forbidden, unauthorized } from "../auth/session.js";
import { notFound } from "../http/errors.js";

export function respondToAuthorizedWrite(response, status, outcome) {
  switch (outcome.status) {
    case "authorized":
      if (!outcome.resource) {
        return notFound(response);
      }
      return status === 204 ? response.status(status).end() : response.status(status).json(outcome.resource);
    case "unauthenticated":
      return unauthorized(response.set("WWW-Authenticate", "Bearer"));
    case "forbidden":
      return forbidden(response);
    case "out_of_scope":
      return notFound(response);
    default:
      throw new Error("Resultado de autorización desconocido.");
  }
}
