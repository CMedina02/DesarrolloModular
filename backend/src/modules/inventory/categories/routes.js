import express from "express";
import { requireRoles } from "../../../core/auth/session.js";
import { notFound, sendError } from "../../../core/http/errors.js";
import { jsonBody } from "../../../core/http/json.js";
import { pagination } from "../../../core/http/pagination.js";
import { respondToAuthorizedWrite } from "../../../core/security/write-response.js";
import { isUuid, normalizeName } from "../../../core/validation.js";

function requireCategoryId(request, response, next) {
  if (!isUuid(request.params.categoryId)) {
    return sendError(response, 400, "VALIDATION_ERROR", "El identificador de categoría debe ser un UUID.");
  }

  return next();
}

function readName(request, response, next) {
  const { body } = request;
  const name = body && Object.hasOwn(body, "name") && Object.keys(body).length === 1
    ? normalizeName(body.name, 100)
    : null;

  if (!name) {
    return sendError(response, 400, "VALIDATION_ERROR", "Envía únicamente un nombre de 1 a 100 caracteres.");
  }

  request.categoryName = name;
  return next();
}

async function respondToCategoryWrite(response, status, save) {
  try {
    return respondToAuthorizedWrite(response, status, await save());
  } catch (error) {
    if (error.code === "23505" && error.constraint === "categories_business_name_ci_uniq") {
      return sendError(response, 409, "CONFLICT", "Ya existe una categoría con ese nombre.");
    }
    if (["23001", "23503"].includes(error.code) && error.constraint === "products_category_same_business_fk") {
      return sendError(response, 409, "CONFLICT", "La categoría tiene productos asociados.");
    }

    throw error;
  }
}

export function createCategoryRouter({ categories, writeCategories }) {
  const router = express.Router();
  const adminOnly = requireRoles("ADMIN");

  router.route("/categories")
    .get(async (request, response) => {
      const page = pagination(request.query);
      if (!page) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa limit y offset.");
      }

      const items = await categories.list(request.businessId, page);
      return response.json({ items, ...page });
    })
    .post(adminOnly, jsonBody, readName, (request, response) =>
      respondToCategoryWrite(response, 201, () =>
        writeCategories(request.authUser, request.businessId, (client) =>
          categories.create(client, request.businessId, request.categoryName)
        )
      )
    );

  router.route("/categories/:categoryId")
    .get(requireCategoryId, async (request, response) => {
      const category = await categories.findById(request.businessId, request.params.categoryId);
      return category ? response.json(category) : notFound(response);
    })
    .patch(adminOnly, requireCategoryId, jsonBody, readName, (request, response) =>
      respondToCategoryWrite(response, 200, () =>
        writeCategories(request.authUser, request.businessId, (client) =>
          categories.update(client, request.businessId, request.params.categoryId, request.categoryName)
        )
      )
    )
    .delete(adminOnly, requireCategoryId, (request, response) =>
      respondToCategoryWrite(response, 204, () =>
        writeCategories(request.authUser, request.businessId, (client) =>
          categories.remove(client, request.businessId, request.params.categoryId)
        )
      )
    );

  return router;
}
