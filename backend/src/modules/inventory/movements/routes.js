import express from "express";
import { forbidden } from "../../../core/auth/session.js";
import { sendError } from "../../../core/http/errors.js";
import { jsonBody } from "../../../core/http/json.js";
import { respondToAuthorizedWrite } from "../../../core/security/write-response.js";
import { movementInput } from "./input.js";
import { calculateStock, StockError } from "./stock.js";

export function createMovementRouter({ products, movements, writeInventory }) {
  const router = express.Router();

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
