import { errors, jwtVerify, SignJWT } from "jose";
import { isUuid } from "../validation.js";

const issuer = "desarrollo-modular";
const audience = "desarrollo-modular-api";
const algorithm = "HS256";
const lifetime = 15 * 60;

export function createAccessTokens(secret) {
  return {
    expiresIn: lifetime,

    issue(userId) {
      const now = Math.floor(Date.now() / 1000);
      return new SignJWT()
        .setProtectedHeader({ alg: algorithm, typ: "JWT" })
        .setIssuer(issuer)
        .setAudience(audience)
        .setSubject(userId)
        .setIssuedAt(now)
        .setExpirationTime(now + lifetime)
        .sign(secret);
    },

    async verify(token) {
      try {
        const { payload } = await jwtVerify(token, secret, {
          algorithms: [algorithm],
          typ: "JWT",
          issuer,
          audience,
          requiredClaims: ["exp", "iat", "sub"],
          maxTokenAge: lifetime,
        });
        return isUuid(payload.sub) ? payload.sub : null;
      } catch (error) {
        if (error instanceof errors.JOSEError) {
          return null;
        }

        throw error;
      }
    },
  };
}
