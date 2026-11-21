import express from "express";
import { rateLimit } from "express-rate-limit";
import { sendError } from "../http/errors.js";
import { normalizeEmail } from "./input.js";
import { isValidPassword, verifyPassword } from "./password.js";

function unauthorized(response) {
  return sendError(response, 401, "UNAUTHENTICATED", "Credenciales o sesión no válidas.");
}

export function createAuthRouter({ users, tokens }) {
  const router = express.Router();
  const limitLogin = rateLimit({
    limit: 10,
    windowMs: 60_000,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    handler: (_request, response) =>
      sendError(response, 429, "TOO_MANY_REQUESTS", "Demasiados intentos. Vuelve a intentarlo más tarde."),
  });

  router.use((_request, response, next) => {
    response.set("Cache-Control", "no-store");
    next();
  });

  router.post("/login", limitLogin, express.json({ limit: "4kb", inflate: false }), async (request, response) => {
    const mediaType = request.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
    if (mediaType !== "application/json") {
      return sendError(response, 415, "UNSUPPORTED_MEDIA_TYPE", "Envía JSON sin compresión en application/json.");
    }

    const { email: inputEmail, password, ...unexpected } = request.body ?? {};
    const email = normalizeEmail(inputEmail);
    if (!email || !isValidPassword(password) || Object.keys(unexpected).length > 0) {
      return sendError(response, 400, "VALIDATION_ERROR", "Revisa el correo y la contraseña.");
    }

    const user = await users.findByEmail(email);
    const valid = await verifyPassword(password, user?.password_hash);
    if (!user || !valid) {
      return unauthorized(response);
    }

    const { password_hash: _passwordHash, ...profile } = user;
    return response.json({
      access_token: await tokens.issue(user.id),
      token_type: "Bearer",
      expires_in: tokens.expiresIn,
      user: profile,
    });
  });

  router.get("/me", async (request, response) => {
    const authorization = request.get("authorization") ?? "";
    const token = /^Bearer +([A-Za-z0-9_.-]+)$/i.exec(authorization)?.[1];
    const id = token ? await tokens.verify(token) : null;
    const user = id ? await users.findById(id) : null;

    if (!user) {
      response.set("WWW-Authenticate", "Bearer");
      return unauthorized(response);
    }

    return response.json(user);
  });

  return router;
}
