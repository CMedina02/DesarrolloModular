import express from "express";
import { requireRoles } from "../auth/session.js";
import { notFound, sendError } from "../http/errors.js";
import { jsonBody } from "../http/json.js";
import { requireBusinessScope } from "../security/business-scope.js";
import { respondToAuthorizedWrite } from "../security/write-response.js";
import { moduleKeys } from "./catalog.js";

export function createModuleRouter({ businessModules, requireSession, authorizedWrite }) {
  const router = express.Router();

  router.get(
    "/:businessId/modules",
    requireSession,
    requireRoles("PLATFORM_ADMIN", "ADMIN", "EMPLOYEE"),
    requireBusinessScope,
    async (request, response) => {
      const modules = await businessModules.list(request.businessId);
      return modules ? response.json(modules) : notFound(response);
    }
  );

  router.put(
    "/:businessId/modules/:moduleKey",
    requireSession,
    requireRoles("PLATFORM_ADMIN"),
    requireBusinessScope,
    jsonBody,
    async (request, response) => {
      const key = request.params.moduleKey;
      const { body } = request;
      if (!moduleKeys.includes(key)) {
        return sendError(response, 400, "VALIDATION_ERROR", "La clave del módulo no está disponible.");
      }
      if (typeof body?.enabled !== "boolean" || Object.keys(body).length !== 1) {
        return sendError(response, 400, "VALIDATION_ERROR", "Envía únicamente enabled como valor booleano.");
      }

      const outcome = await authorizedWrite(request.authUser, (client) =>
        businessModules.setEnabled(client, request.businessId, key, body.enabled)
      );
      return respondToAuthorizedWrite(response, 200, outcome);
    }
  );

  return router;
}
