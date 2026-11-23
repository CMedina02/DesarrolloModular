import express from "express";
import { hashPassword } from "../auth/password.js";
import { requireRoles } from "../auth/session.js";
import { notFound, sendError } from "../http/errors.js";
import { jsonBody } from "../http/json.js";
import { requireBusinessScope } from "../security/business-scope.js";
import { respondToAuthorizedWrite } from "../security/write-response.js";
import { isUuid } from "../validation.js";
import { businessInput, pagination, userInput } from "./input.js";

function mayManageAdmins(request) {
  return request.authUser.role === "PLATFORM_ADMIN";
}

async function respondToWrite(response, status, save) {
  try {
    return respondToAuthorizedWrite(response, status, await save());
  } catch (error) {
    if (error.code === "23505" && error.constraint === "users_email_ci_uniq") {
      return sendError(response, 409, "CONFLICT", "El correo ya está registrado.");
    }
    if (error.code === "23503" && error.constraint === "users_business_id_fkey") {
      return notFound(response);
    }

    throw error;
  }
}

export function createBusinessRouter({ businesses, businessUsers, requireSession, authorizedWrite }) {
  const router = express.Router();
  const platformOnly = [requireSession, requireRoles("PLATFORM_ADMIN")];
  const companyAccess = [requireSession, requireRoles("PLATFORM_ADMIN", "ADMIN"), requireBusinessScope];

  router.route("/")
    .get(platformOnly, async (request, response) => {
      const page = pagination(request.query);
      if (!page) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa limit y offset.");
      }

      const items = await businesses.list(page);
      return response.json({ items, ...page });
    })
    .post(platformOnly, jsonBody, async (request, response) => {
      const input = businessInput(request.body, true);
      if (!input) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos de la empresa.");
      }

      return respondToWrite(response, 201, () =>
        authorizedWrite(request.authUser, (client) => businesses.create(client, input))
      );
    });

  router.route("/:businessId")
    .get(companyAccess, async (request, response) => {
      const business = await businesses.findById(request.businessId);
      return business ? response.json(business) : notFound(response);
    })
    .patch(platformOnly, requireBusinessScope, jsonBody, async (request, response) => {
      const input = businessInput(request.body, false);
      if (!input) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos de la empresa.");
      }

      return respondToWrite(response, 200, () =>
        authorizedWrite(request.authUser, (client) =>
          businesses.update(client, request.businessId, input)
        )
      );
    });

  router.route("/:businessId/users")
    .get(companyAccess, async (request, response) => {
      const page = pagination(request.query);
      if (!page) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa limit y offset.");
      }

      const { businessId } = request;
      if (!(await businesses.findById(businessId))) {
        return notFound(response);
      }

      const items = await businessUsers.list(businessId, mayManageAdmins(request), page);
      return response.json({ items, ...page });
    })
    .post(companyAccess, jsonBody, async (request, response) => {
      const input = userInput(request.body, true);
      if (!input) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos y la contraseña del usuario.");
      }
      if (!mayManageAdmins(request) && input.role === "ADMIN") {
        return sendError(response, 403, "FORBIDDEN", "Solo el administrador de plataforma puede asignar el rol ADMIN.");
      }

      const { businessId } = request;
      if (!(await businesses.findById(businessId))) {
        return notFound(response);
      }

      const { password, ...profile } = input;
      const passwordHash = await hashPassword(password);
      return respondToWrite(response, 201, () =>
        authorizedWrite(request.authUser, (client) =>
          businessUsers.create(client, businessId, { ...profile, passwordHash })
        )
      );
    });

  router.patch("/:businessId/users/:userId", companyAccess, jsonBody, async (request, response) => {
    const { userId } = request.params;
    if (!isUuid(userId)) {
      return sendError(response, 400, "VALIDATION_ERROR", "El identificador de usuario debe ser un UUID.");
    }

    const input = userInput(request.body, false);
    if (!input) {
      return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos del usuario.");
    }

    const platformAdmin = mayManageAdmins(request);
    if (!platformAdmin && input.role === "ADMIN") {
      return sendError(response, 403, "FORBIDDEN", "Solo el administrador de plataforma puede asignar el rol ADMIN.");
    }

    return respondToWrite(response, 200, () =>
      authorizedWrite(request.authUser, (client) =>
        businessUsers.update(client, request.businessId, userId, platformAdmin, input)
      )
    );
  });

  return router;
}
