import express from "express";
import { requireRoles } from "../../../core/auth/session.js";
import { notFound, sendError } from "../../../core/http/errors.js";
import { jsonBody } from "../../../core/http/json.js";
import { pagination } from "../../../core/http/pagination.js";
import { respondToAuthorizedWrite } from "../../../core/security/write-response.js";
import { isUuid } from "../../../core/validation.js";
import { fitsUnit, productFilters, productInput } from "./input.js";

class ProductWriteError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const wholeUnitMessage = "Piezas y cajas requieren cantidades enteras.";

function requireProductId(request, response, next) {
  if (!isUuid(request.params.productId)) {
    return sendError(response, 400, "VALIDATION_ERROR", "El identificador de producto debe ser un UUID.");
  }

  return next();
}

async function respondToProductWrite(response, status, save) {
  try {
    return respondToAuthorizedWrite(response, status, await save());
  } catch (error) {
    if (error instanceof ProductWriteError) {
      return sendError(response, error.status, error.code, error.message);
    }
    if (error.code === "23505" && error.constraint === "products_business_sku_ci_uniq") {
      return sendError(response, 409, "CONFLICT", "Ya existe un producto con ese SKU.");
    }
    if (error.code === "23503" && error.constraint === "products_category_same_business_fk") {
      return notFound(response);
    }

    throw error;
  }
}

async function updateProduct(products, client, businessId, productId, changes) {
  const current = await products.lockForUpdate(client, businessId, productId);
  if (!current) {
    return undefined;
  }

  const unit = changes.unit ?? current.unit;
  if (unit !== current.unit && await products.hasMovements(client, businessId, productId)) {
    throw new ProductWriteError(409, "CONFLICT", "El producto tiene movimientos y su unidad debe conservarse.");
  }
  const minStock = changes.min_stock ?? current.min_stock;
  if (!fitsUnit(unit, minStock) || !fitsUnit(unit, current.stock_quantity)) {
    throw new ProductWriteError(400, "VALIDATION_ERROR", wholeUnitMessage);
  }

  return products.update(client, businessId, productId, changes);
}

export function createProductRouter({ products, writeInventory }) {
  const router = express.Router();
  const adminOnly = requireRoles("ADMIN");

  router.route("/products")
    .get(async (request, response) => {
      const page = pagination(request.query);
      const filters = productFilters(request.query);
      if (!page || !filters) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa la paginación y los filtros de productos.");
      }

      const activeOnly = request.authUser.role === "EMPLOYEE";
      const items = await products.list(request.businessId, { ...page, ...filters, activeOnly });
      return response.json({ items, ...page });
    })
    .post(adminOnly, jsonBody, (request, response) => {
      const product = productInput(request.body, true);
      if (!product) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos del producto.");
      }
      if (!fitsUnit(product.unit, product.min_stock ?? "0")) {
        return sendError(response, 400, "VALIDATION_ERROR", wholeUnitMessage);
      }

      return respondToProductWrite(response, 201, () =>
        writeInventory(request.authUser, request.businessId, (client) =>
          products.create(client, request.businessId, product)
        )
      );
    });

  router.route("/products/:productId")
    .get(requireProductId, async (request, response) => {
      const activeOnly = request.authUser.role === "EMPLOYEE";
      const product = await products.findById(request.businessId, request.params.productId, activeOnly);
      return product ? response.json(product) : notFound(response);
    })
    .patch(adminOnly, requireProductId, jsonBody, (request, response) => {
      const changes = productInput(request.body, false);
      if (!changes) {
        return sendError(response, 400, "VALIDATION_ERROR", "Revisa los datos del producto.");
      }

      return respondToProductWrite(response, 200, () =>
        writeInventory(request.authUser, request.businessId, (client) =>
          updateProduct(products, client, request.businessId, request.params.productId, changes)
        )
      );
    });

  return router;
}
