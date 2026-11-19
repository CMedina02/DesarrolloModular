-- INVENTARIO COMERCIAL 1.0 | T02 | PostgreSQL 13+
-- Ejecutar sobre una base de datos vacía; UTF-8.
-- Migración inicial: cinco tablas, multiempresa y cantidades decimales.
BEGIN;

CREATE TABLE businesses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(160) NOT NULL CHECK (length(btrim(name)) > 0),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id   UUID REFERENCES businesses(id) ON DELETE RESTRICT,
    name          VARCHAR(150) NOT NULL CHECK (length(btrim(name)) > 0),
    email         VARCHAR(255) NOT NULL CHECK (email = btrim(email) AND position('@' IN email) > 1),
    password_hash TEXT NOT NULL CHECK (length(password_hash) > 0),
    role          VARCHAR(20) NOT NULL CHECK (role IN ('PLATFORM_ADMIN', 'ADMIN', 'EMPLOYEE')),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_platform_scope_chk CHECK (
        (role = 'PLATFORM_ADMIN' AND business_id IS NULL)
        OR
        (role IN ('ADMIN', 'EMPLOYEE') AND business_id IS NOT NULL)
    ),
    CONSTRAINT users_business_id_id_uniq UNIQUE (business_id, id)
);
CREATE UNIQUE INDEX users_email_ci_uniq ON users (lower(email));
CREATE INDEX users_business_idx ON users (business_id);

CREATE TABLE categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    name        VARCHAR(100) NOT NULL CHECK (name = btrim(name) AND length(name) > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT categories_business_id_id_uniq UNIQUE (business_id, id)
);
CREATE UNIQUE INDEX categories_business_name_ci_uniq ON categories (business_id, lower(name));

CREATE TABLE products (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    category_id    UUID NOT NULL,
    sku            VARCHAR(60) NOT NULL CHECK (sku = btrim(sku) AND length(sku) > 0),
    name           VARCHAR(180) NOT NULL CHECK (name = btrim(name) AND length(name) > 0),
    unit           VARCHAR(10) NOT NULL CHECK (unit IN ('PZA', 'CAJA', 'KG', 'M', 'L')),
    cost_price     NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (cost_price >= 0),
    sale_price     NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (sale_price >= 0),
    stock_quantity NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    min_stock      NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT products_category_same_business_fk
        FOREIGN KEY (business_id, category_id)
        REFERENCES categories (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT products_business_id_id_uniq UNIQUE (business_id, id),
    CONSTRAINT products_whole_units_chk CHECK (
        unit NOT IN ('PZA', 'CAJA')
        OR (stock_quantity = trunc(stock_quantity) AND min_stock = trunc(min_stock))
    )
);
CREATE UNIQUE INDEX products_business_sku_ci_uniq ON products (business_id, lower(sku));
CREATE INDEX products_business_category_idx ON products (business_id, category_id);
CREATE INDEX products_business_active_idx ON products (business_id, is_active);

CREATE TABLE stock_movements (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id    UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    product_id     UUID NOT NULL,
    user_id        UUID NOT NULL,
    movement_type  VARCHAR(12) NOT NULL CHECK (movement_type IN ('IN', 'OUT', 'ADJUSTMENT')),
    quantity_delta NUMERIC(14, 3) NOT NULL,
    stock_before   NUMERIC(14, 3) NOT NULL CHECK (stock_before >= 0),
    stock_after    NUMERIC(14, 3) NOT NULL CHECK (stock_after >= 0),
    reason         TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT movements_product_same_business_fk
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT movements_user_same_business_fk
        FOREIGN KEY (business_id, user_id)
        REFERENCES users (business_id, id) ON DELETE RESTRICT,
    CONSTRAINT movement_delta_type_chk CHECK (
        (movement_type = 'IN' AND quantity_delta > 0)
        OR (movement_type = 'OUT' AND quantity_delta < 0)
        OR (movement_type = 'ADJUSTMENT' AND quantity_delta <> 0)
    ),
    CONSTRAINT movement_balance_chk CHECK (stock_after = stock_before + quantity_delta),
    CONSTRAINT movement_reason_chk CHECK (
        movement_type = 'IN' OR (reason IS NOT NULL AND length(btrim(reason)) > 0)
    )
);
CREATE INDEX stock_movements_product_history_idx
    ON stock_movements (business_id, product_id, created_at DESC);
CREATE INDEX stock_movements_business_history_idx
    ON stock_movements (business_id, created_at DESC);

-- PZA y CAJA no admiten fracciones en cantidades de movimientos.
CREATE FUNCTION validate_stock_movement_unit_quantity() RETURNS TRIGGER AS $$
DECLARE
    product_unit VARCHAR(10);
BEGIN
    SELECT unit INTO product_unit FROM products
    WHERE business_id = NEW.business_id AND id = NEW.product_id;

    IF product_unit IN ('PZA', 'CAJA') AND (
        NEW.quantity_delta <> trunc(NEW.quantity_delta)
        OR NEW.stock_before <> trunc(NEW.stock_before)
        OR NEW.stock_after <> trunc(NEW.stock_after)
    ) THEN
        RAISE EXCEPTION 'PZA y CAJA requieren cantidades enteras';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER stock_movements_unit_quantity_trg
    BEFORE INSERT OR UPDATE ON stock_movements
    FOR EACH ROW EXECUTE FUNCTION validate_stock_movement_unit_quantity();

-- Los productos comienzan en 0; el inventario inicial se registra como IN.
CREATE FUNCTION reject_nonzero_initial_stock() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.stock_quantity <> 0 THEN
        RAISE EXCEPTION 'Un producto nuevo debe comenzar con stock 0; registre una entrada inicial';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER products_initial_stock_zero_trg
    BEFORE INSERT ON products
    FOR EACH ROW EXECUTE FUNCTION reject_nonzero_initial_stock();

-- Auditoría inmutable: no modificar ni borrar movimientos existentes.
CREATE FUNCTION reject_stock_movement_mutation() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Los movimientos de inventario son inmutables; registre un ajuste';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER stock_movements_immutable_trg
    BEFORE UPDATE OR DELETE ON stock_movements
    FOR EACH ROW EXECUTE FUNCTION reject_stock_movement_mutation();

COMMIT;
