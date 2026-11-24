import express from "express";
import { forbidden, requireRoles } from "../../../core/auth/session.js";
import { sendError } from "../../../core/http/errors.js";
import { jsonBody } from "../../../core/http/json.js";
import { pagination } from "../../../core/http/pagination.js";
import { respondToAuthorizedWrite } from "../../../core/security/write-response.js";
import { movementFilters, movementInput } from "./input.js";
import { calculateStock, StockError } from "./stock.js";

export function createMovementRouter({ products, movements, writeInventory }) {
  const router = express.Router();

  router.get("/movements", requireRoles("ADMIN"), async (request, response) => {
    const page = pagination(request.query);
    const filters = movementFilters(request.query);
    if (!page || !filters) {
      return sendError(response, 400, "VALIDATION_ERROR", "Revisa la paginación y los filtros de movimientos.");
    }

    const items = await movements.list(request.businessId, { ...page, ...filters });
    return response.json({ items, ...page });
  });

  router.post("/movements", jsonBody, async (request, response) => {
    const movement = movementInput(request.body);
    if (!movement) {
      return sendError(response, 400, "VALIDATION_ERROR", "Revisa el tipo, la cantidad y el motivo del movimiento.");
    }

    const { authUser, businessId } = request;
    if (movement.type === "ADJUSTMENT" && authUser.role !== "ADMIN") {
      return forbidden(response);
    }

    try {
      const outcome = await writeInventory(authUser, businessId, async (client) => {
        const product = await products.lockForUpdate(client, businessId, movement.productId);
        if (!product) {
          return undefined;
        }

        const stock = calculateStock(product, movement);
        await products.setStock(client, businessId, movement.productId, stock.after);
        return movements.create(client, { ...movement, ...stock, businessId, userId: authUser.id });
      });

      return respondToAuthorizedWrite(response, 201, outcome);
    } catch (error) {
      if (error instanceof StockError) {
        return sendError(response, error.status, error.code, error.message);
      }

      throw error;
    }
  });

  return router;
}
