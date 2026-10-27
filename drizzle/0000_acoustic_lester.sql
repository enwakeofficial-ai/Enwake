CREATE TABLE `orders` (
	`id` text PRIMARY KEY NOT NULL,
	`request_id` text NOT NULL,
	`access_token` text NOT NULL,
	`user_id` text,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`phone` text NOT NULL,
	`address` text NOT NULL,
	`city` text NOT NULL,
	`state` text NOT NULL,
	`pin` text NOT NULL,
	`note` text NOT NULL,
	`items` text NOT NULL,
	`subtotal` integer NOT NULL,
	`discount` integer NOT NULL,
	`shipping` integer NOT NULL,
	`total` integer NOT NULL,
	`coupon` text NOT NULL,
	`status` text NOT NULL,
	`payment` text NOT NULL,
	`payment_method` text NOT NULL,
	`gateway_order` text,
	`gateway_payment` text,
	`tracking` text DEFAULT '' NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `orders_request_id_unique` ON `orders` (`request_id`);--> statement-breakpoint
CREATE TABLE `products` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`category` text NOT NULL,
	`scent` text NOT NULL,
	`notes` text NOT NULL,
	`description` text NOT NULL,
	`price` integer NOT NULL,
	`original_price` integer NOT NULL,
	`stock` integer NOT NULL,
	`size` text NOT NULL,
	`burn` text NOT NULL,
	`image` text NOT NULL,
	`image_position` integer DEFAULT -1 NOT NULL,
	`visible` integer DEFAULT 1 NOT NULL,
	`sample` integer DEFAULT 1 NOT NULL,
	`badge` text DEFAULT '' NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `settings` (
	`key` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `subscribers` (
	`email` text PRIMARY KEY NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX orders_user_created ON orders(user_id,created_at);
--> statement-breakpoint
CREATE INDEX orders_gateway ON orders(gateway_order);
--> statement-breakpoint
CREATE TRIGGER reserve_order_stock BEFORE INSERT ON orders BEGIN
 SELECT CASE WHEN EXISTS (
 SELECT 1 FROM json_each(NEW.items) x LEFT JOIN products p ON p.id=json_extract(x.value,'$.id')
 WHERE p.id IS NULL OR p.visible!=1 OR json_extract(x.value,'$.quantity')<1
 OR json_extract(x.value,'$.quantity')!=CAST(json_extract(x.value,'$.quantity') AS INTEGER)
 OR p.stock<json_extract(x.value,'$.quantity') OR p.price!=json_extract(x.value,'$.price')
 ) THEN RAISE(ABORT,'Stock or price changed') END;
 UPDATE products SET stock=stock-(SELECT json_extract(x.value,'$.quantity') FROM json_each(NEW.items) x WHERE json_extract(x.value,'$.id')=products.id)
 WHERE id IN (SELECT json_extract(value,'$.id') FROM json_each(NEW.items));
END;
--> statement-breakpoint
CREATE TRIGGER restore_cancelled_stock AFTER UPDATE OF status ON orders WHEN NEW.status='Cancelled' AND OLD.status!='Cancelled' BEGIN
 UPDATE products SET stock=stock+(SELECT json_extract(x.value,'$.quantity') FROM json_each(NEW.items) x WHERE json_extract(x.value,'$.id')=products.id)
 WHERE id IN (SELECT json_extract(value,'$.id') FROM json_each(NEW.items));
END;
