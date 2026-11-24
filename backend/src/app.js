import express from "express";
import { createAuthRouter } from "./core/auth/routes.js";
import { createRequireSession, requireRoles } from "./core/auth/session.js";
import { createBusinessRouter } from "./core/businesses/routes.js";
import { notFound, sendError } from "./core/http/errors.js";
import { createModuleWrite, moduleDisabled, ModuleDisabledError, requireEnabledModule } from "./core/modules/access.js";
import { inventoryModuleKey } from "./core/modules/catalog.js";
import { createModuleRouter } from "./core/modules/routes.js";
import { requireBusinessScope } from "./core/security/business-scope.js";
import { createCategoryRouter } from "./modules/inventory/categories/routes.js";
import { createMovementRouter } from "./modules/inventory/movements/routes.js";
import { createProductRouter } from "./modules/inventory/products/routes.js";

const bodyErrors = {
  "entity.parse.failed": [400, "VALIDATION_ERROR", "El cuerpo JSON no es válido."],
  "request.size.invalid": [400, "VALIDATION_ERROR", "El cuerpo de la solicitud no es válido."],
  "entity.too.large": [413, "PAYLOAD_TOO_LARGE", "El cuerpo supera el tamaño permitido."],
  "charset.unsupported": [415, "UNSUPPORTED_MEDIA_TYPE", "La codificación del cuerpo no es compatible."],
  "encoding.unsupported": [415, "UNSUPPORTED_MEDIA_TYPE", "Envía JSON sin compresión en application/json."],
};

export function createApp({ checkDatabase, auth, businesses, businessUsers, businessModules, authorizedWrite, categories, products, movements, webDirectory }) {
  const app = express();
  app.disable("x-powered-by");

  app.get("/health", (_request, response) => {
    response.set("Cache-Control", "no-store").json({ status: "ok" });
  });

  app.get("/health/db", async (_request, response) => {
    response.set("Cache-Control", "no-store");

    try {
      await checkDatabase();
    } catch {
      return sendError(response, 503, "DATABASE_UNAVAILABLE", "PostgreSQL no está disponible.");
    }

    return response.json({ status: "ok" });
  });

  const requireSession = createRequireSession(auth);
  app.use("/api/v1/auth", createAuthRouter(auth, requireSession));
  app.use("/api/v1/businesses", createBusinessRouter({
    businesses,
    businessUsers,
    requireSession,
    authorizedWrite,
  }));

  app.use("/api/v1/businesses", createModuleRouter({ businessModules, requireSession, authorizedWrite }));
  const writeInventory = createModuleWrite(authorizedWrite, businessModules, inventoryModuleKey);
  app.use(
    "/api/v1/businesses/:businessId/inventory",
    requireSession,
    requireRoles("ADMIN", "EMPLOYEE"),
    requireBusinessScope,
    requireEnabledModule(businessModules, inventoryModuleKey),
    createCategoryRouter({ categories, writeCategories: writeInventory }),
    createProductRouter({ products, writeInventory }),
    createMovementRouter({ products, movements, writeInventory })
  );

  if (webDirectory) {
    app.use("/api", (_request, response) => notFound(response));
    app.use(express.static(webDirectory, {
      redirect: false,
      setHeaders: (response) => response.setHeader("X-Content-Type-Options", "nosniff"),
    }));
  }

  app.use((_request, response) => notFound(response));

  app.use((error, _request, response, next) => {
    if (response.headersSent) {
      return next(error);
    }

    if (error instanceof ModuleDisabledError) {
      return moduleDisabled(response);
    }

    if (Object.hasOwn(bodyErrors, error.type)) {
      return sendError(response, ...bodyErrors[error.type]);
    }

    console.error("Error inesperado al atender una solicitud HTTP.");
    return sendError(response, 500, "INTERNAL_ERROR", "No se pudo completar la operación.");
  });

  return app;
}
