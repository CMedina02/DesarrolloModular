import express from "express";
import { sendError } from "./errors.js";

function requireJson(request, response, next) {
  const mediaType = request.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (mediaType !== "application/json") {
    return sendError(response, 415, "UNSUPPORTED_MEDIA_TYPE", "Envía JSON sin compresión en application/json.");
  }

  return next();
}

export const jsonBody = [requireJson, express.json({ limit: "4kb", inflate: false })];
