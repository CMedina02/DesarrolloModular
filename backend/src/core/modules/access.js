import { sendError } from "../http/errors.js";

export class ModuleDisabledError extends Error {}

export function moduleDisabled(response) {
  return sendError(response, 403, "FORBIDDEN", "Este módulo está deshabilitado para la empresa.");
}

export function requireEnabledModule(businessModules, key) {
  return async function checkModule(request, response, next) {
    if (!(await businessModules.isEnabled(request.businessId, key))) {
      return moduleDisabled(response);
    }

    return next();
  };
}

export function createModuleWrite(authorizedWrite, businessModules, key) {
  return (session, businessId, operation) => authorizedWrite(session, async (client) => {
    if (!(await businessModules.lockEnabled(client, businessId, key))) {
      throw new ModuleDisabledError();
    }

    return operation(client);
  });
}
