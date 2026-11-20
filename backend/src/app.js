import express from "express";

function sendError(response, status, code, message) {
  return response.status(status).json({ error: { code, message } });
}

export function createApp({ checkDatabase }) {
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

  app.use((_request, response) =>
    sendError(response, 404, "NOT_FOUND", "No se encontró el recurso.")
  );

  app.use((error, _request, response, next) => {
    if (response.headersSent) {
      return next(error);
    }

    console.error("Error inesperado al atender una solicitud HTTP.");
    return sendError(response, 500, "INTERNAL_ERROR", "No se pudo completar la operación.");
  });

  return app;
}
