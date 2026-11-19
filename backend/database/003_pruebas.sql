-- Pruebas de integridad SQL. Ejecución en transacción que termina en ROLLBACK.
-- Requiere 001_schema.sql; no necesita 002_datos_demo.sql.
BEGIN;
DO $$
DECLARE
    b1 UUID := gen_random_uuid();
    b2 UUID := gen_random_uuid();
    c1 UUID := gen_random_uuid();
    c2 UUID := gen_random_uuid();
    u1 UUID := gen_random_uuid();
    u2 UUID := gen_random_uuid();
    p1 UUID := gen_random_uuid();
    p2 UUID := gen_random_uuid();
    m1 UUID := gen_random_uuid();
    current_stock NUMERIC(14,3);
    caught BOOLEAN;
BEGIN
    INSERT INTO businesses (id, name) VALUES (b1, 'Negocio Test A'), (b2, 'Negocio Test B');
    INSERT INTO users (id, business_id, name, email, password_hash, role, is_active) VALUES
        (u1, b1, 'Operador test A', 'qa+' || b1::text || '@example.invalid', 'TEST_NOT_A_REAL_HASH', 'EMPLOYEE', FALSE),
        (u2, b2, 'Operador test B', 'qa+' || b2::text || '@example.invalid', 'TEST_NOT_A_REAL_HASH', 'EMPLOYEE', FALSE);
    INSERT INTO categories (id, business_id, name) VALUES
        (c1, b1, 'Materiales'), (c2, b2, 'Materiales');
    INSERT INTO products (id, business_id, category_id, sku, name, unit, min_stock) VALUES
        (p1, b1, c1, 'KG-001', 'Clavos por kilo', 'KG', 2.500),
        (p2, b2, c2, 'KG-001', 'Clavos en otro negocio', 'KG', 1.000);

    -- Un SKU igual entre negocios distintos es válido.
    SELECT stock_quantity INTO current_stock FROM products WHERE id = p1;
    IF current_stock <> 0 THEN RAISE EXCEPTION 'FAIL: inventario inicial'; END IF;

    -- No crear productos con existencia inicial distinta de cero.
    caught := FALSE;
    BEGIN
        INSERT INTO products (business_id, category_id, sku, name, unit, stock_quantity)
        VALUES (b1, c1, 'ERR-STOCK', 'Incorrecto', 'KG', 2.000);
    EXCEPTION WHEN raise_exception THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: se permitió stock inicial no cero'; END IF;

    -- Categoría de otro negocio: FK compuesta debe impedirlo.
    caught := FALSE;
    BEGIN
        INSERT INTO products (business_id, category_id, sku, name, unit)
        VALUES (b1, c2, 'ERR-CAT', 'Incorrecto', 'KG');
    EXCEPTION WHEN foreign_key_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: categoría de otro negocio'; END IF;

    -- SKU duplicado, incluso con distinta capitalización.
    caught := FALSE;
    BEGIN
        INSERT INTO products (business_id, category_id, sku, name, unit)
        VALUES (b1, c1, 'kg-001', 'Duplicado', 'KG');
    EXCEPTION WHEN unique_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: SKU duplicado'; END IF;

    -- Entrada de 12.500 kg: operación y historial en la misma transacción.
    UPDATE products SET stock_quantity = stock_quantity + 12.500 WHERE id = p1;
    INSERT INTO stock_movements (id, business_id, product_id, user_id, movement_type,
                                 quantity_delta, stock_before, stock_after, reason)
    VALUES (m1, b1, p1, u1, 'IN', 12.500, 0, 12.500, 'Inventario inicial');

    -- Salida mayor al disponible: no se aceptan cantidades negativas.
    caught := FALSE;
    BEGIN
        UPDATE products SET stock_quantity = stock_quantity - 13 WHERE id = p1;
    EXCEPTION WHEN check_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: stock negativo'; END IF;

    -- Motivo obligatorio en salidas.
    caught := FALSE;
    BEGIN
        INSERT INTO stock_movements (business_id, product_id, user_id, movement_type,
                                     quantity_delta, stock_before, stock_after)
        VALUES (b1, p1, u1, 'OUT', -1, 12.500, 11.500);
    EXCEPTION WHEN check_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: salida sin motivo'; END IF;

    -- Un usuario de otro negocio no puede firmar un movimiento.
    caught := FALSE;
    BEGIN
        INSERT INTO stock_movements (business_id, product_id, user_id, movement_type,
                                     quantity_delta, stock_before, stock_after, reason)
        VALUES (b1, p1, u2, 'OUT', -1, 12.500, 11.500, 'Prueba');
    EXCEPTION WHEN foreign_key_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: usuario de otro negocio'; END IF;

    -- Salida válida de 3.250 kg.
    UPDATE products SET stock_quantity = stock_quantity - 3.250 WHERE id = p1;
    INSERT INTO stock_movements (business_id, product_id, user_id, movement_type,
                                 quantity_delta, stock_before, stock_after, reason)
    VALUES (b1, p1, u1, 'OUT', -3.250, 12.500, 9.250, 'Consumo registrado');

    SELECT stock_quantity INTO current_stock FROM products WHERE id = p1;
    IF current_stock <> 9.250 THEN RAISE EXCEPTION 'FAIL: stock final decimal'; END IF;

    -- No editar historia registrada.
    caught := FALSE;
    BEGIN
        UPDATE stock_movements SET reason = 'Modificación prohibida' WHERE id = m1;
    EXCEPTION WHEN raise_exception THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: modificación de historial'; END IF;

    -- Para unidades discretas no aceptar fracciones en stock actual.
    INSERT INTO products (business_id, category_id, sku, name, unit)
    VALUES (b1, c1, 'PZA-1', 'Pieza de prueba', 'PZA');
    caught := FALSE;
    BEGIN
        UPDATE products SET stock_quantity = 1.500 WHERE business_id = b1 AND sku = 'PZA-1';
    EXCEPTION WHEN check_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: piezas fraccionarias'; END IF;

    -- Las cantidades de movimientos también deben ser enteras para PZA/CAJA.
    caught := FALSE;
    BEGIN
        INSERT INTO stock_movements (business_id, product_id, user_id, movement_type,
                                     quantity_delta, stock_before, stock_after, reason)
        VALUES (b1, (SELECT id FROM products WHERE business_id = b1 AND sku = 'PZA-1'),
                u1, 'IN', 1.500, 0, 1.500, 'Prueba fraccionaria');
    EXCEPTION WHEN raise_exception THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: movimiento fraccionario en PZA'; END IF;

    -- Categorías duplicadas sin distinguir mayúsculas.
    caught := FALSE;
    BEGIN
        INSERT INTO categories (business_id, name) VALUES (b1, 'materiales');
    EXCEPTION WHEN unique_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: categoría duplicada'; END IF;

    -- Los precios negativos se rechazan.
    caught := FALSE;
    BEGIN
        UPDATE products SET sale_price = -1 WHERE id = p1;
    EXCEPTION WHEN check_violation THEN caught := TRUE;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'FAIL: precio negativo'; END IF;

    RAISE NOTICE 'OK: pruebas de integridad, multiempresa, stock, decimales e historial completadas';
END;
$$;
ROLLBACK;
