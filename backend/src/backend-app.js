import { createApp } from "./app.js";
import { createAccessTokens } from "./core/auth/token.js";
import { createAuthUsers } from "./core/auth/users.js";
import { createBusinesses } from "./core/businesses/repository.js";
import { checkDatabase } from "./core/database/pool.js";
import { createBusinessModules } from "./core/modules/repository.js";
import { createAuthorizedWrite } from "./core/security/authorized-write.js";
import { createBusinessUsers } from "./core/users/repository.js";
import { createCategories } from "./modules/inventory/categories/repository.js";
import { createMovements } from "./modules/inventory/movements/repository.js";
import { createProducts } from "./modules/inventory/products/repository.js";

export function createBackendApp(pool, jwtSecret, { webDirectory } = {}) {
  return createApp({
    webDirectory,
    checkDatabase: () => checkDatabase(pool),
    authorizedWrite: createAuthorizedWrite(pool),
    businesses: createBusinesses(pool),
    businessUsers: createBusinessUsers(pool),
    businessModules: createBusinessModules(pool),
    categories: createCategories(pool),
    products: createProducts(pool),
    movements: createMovements(pool),
    auth: {
      users: createAuthUsers(pool),
      tokens: createAccessTokens(jwtSecret),
    },
  });
}
