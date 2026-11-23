import { sendError } from "../http/errors.js";

export function requireEnabledModule(businessModules, key) {
  return async function checkModule(request, response, next) {
    if (!(await businessModules.isEnabled(request.businessId, key))) {
      return sendError(response, 403, "FORBIDDEN", "Este módulo está deshabilitado para la empresa.");
    }

    return next();
  };
}
