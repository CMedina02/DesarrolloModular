import express from "express";
import { hashPassword } from "../auth/password.js";
import { requireRoles } from "../auth/session.js";
import { sendError } from "../http/errors.js";
import { jsonBody } from "../http/json.js";
import { isUuid } from "../validation.js";
import { businessInput, pagination, userInput } from "./input.js";

function notFound(response) {
  return sendError(response, 404, "NOT_FOUND", "No se encontró el recurso.");
}

function mayManageAdmins(request) {
  return request.authUser.role === "PLATFORM_ADMIN";
}

function scopeBusiness(request, response, next) {
  const businessId = request.params.businessId;
  if (!isUuid(businessId)) {
    return sendError(response, 400, "VALIDATION_ERROR", "El identificador de empresa debe ser un UUID.");
  }
  if (!mayManageAdmins(request) && request.authUser.business_id !== businessId.toLowerCase()) {
    return notFound(response);
  }

  return next();
}

async function writeUser(response, status, save) {
  try {
    const user = await save();
    return user ? response.status(status).json(user) : notFound(response);
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

export function createBusinessRouter({ businesses, businessUsers, requireSession }) {
  const router = express.Router();
  const platformOnly = [requireSession, requireRoles("PLATFORM_ADMIN")];
  const companyAccess = [requireSession, requireRoles("PLATFORM_ADMIN", "ADMIN"), scopeBusiness];

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

      return response.status(201).json(await businesses.create(input));
    });

  router.route("/:businessId")
    .get(companyAccess, async (request, response) => {
      const business = await businesses.findById(request.params.businessId);
      return business ? response.json(business) : notFound(response);
    })
    .patch(platformOnly, scopeBusiness, jsonBody, async (request, response) => {
      const input = businessInput(request.body, false);
      if (!input) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos de la empresa.");
      }

      const business = await businesses.update(request.params.businessId, input);
      return business ? response.json(business) : notFound(response);
    });

  router.route("/:businessId/users")
    .get(companyAccess, async (request, response) => {
      const page = pagination(request.query);
      if (!page) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa limit y offset.");
      }

      const { businessId } = request.params;
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

      const { businessId } = request.params;
      if (!(await businesses.findById(businessId))) {
        return notFound(response);
      }

      const { password, ...profile } = input;
      const passwordHash = await hashPassword(password);
      return writeUser(response, 201, () => businessUsers.create(businessId, { ...profile, passwordHash }));
    });

  router.patch("/:businessId/users/:userId", companyAccess, jsonBody, async (request, response) => {
    const { businessId, userId } = request.params;
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

    return writeUser(response, 200, () => businessUsers.update(businessId, userId, platformAdmin, input));
  });

  return router;
}
