import { notFound, sendError } from "../http/errors.js";
import { isUuid } from "../validation.js";

export function requireBusinessScope(request, response, next) {
  const requestedId = request.params.businessId;
  if (!isUuid(requestedId)) {
    return sendError(response, 400, "VALIDATION_ERROR", "El identificador de empresa debe ser un UUID.");
  }

  const businessId = requestedId.toLowerCase();
  const actor = request.authUser;
  if (actor.role !== "PLATFORM_ADMIN" && actor.business_id !== businessId) {
    return notFound(response);
  }

  request.businessId = actor.role === "PLATFORM_ADMIN" ? businessId : actor.business_id;
  return next();
}
