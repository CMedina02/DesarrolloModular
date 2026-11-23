import { forbidden, unauthorized } from "../auth/session.js";
import { notFound } from "../http/errors.js";

export function respondToAuthorizedWrite(response, status, outcome) {
  switch (outcome.status) {
    case "authorized":
      return outcome.resource ? response.status(status).json(outcome.resource) : notFound(response);
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
