-- B06: configuración de módulos por empresa.
BEGIN;

CREATE TABLE business_modules (
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    module_key  VARCHAR(64) NOT NULL CHECK (module_key ~ '^[a-z][a-z0-9_]*$'),
    enabled     BOOLEAN NOT NULL,
    PRIMARY KEY (business_id, module_key)
);

COMMIT;
