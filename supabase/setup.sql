-- Run once in a NEW candle-store Supabase project. Does not change Thread in Loops.
begin;
create table public.admin_members(user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now());
create table public.products(
 id text primary key default gen_random_uuid()::text,name text not null check(length(name) between 1 and 100),category text not null,scent text not null,notes text not null default '',description text not null default '',
 price integer not null check(price between 100 and 10000000),original_price integer not null check(original_price>=price),stock integer not null check(stock between 0 and 99999),size text not null default '',burn text not null default '',image text not null,image_position integer not null default -1 check(image_position between -1 and 3),visible integer not null default 0 check(visible in(0,1)),sample integer not null default 0 check(sample in(0,1)),badge text not null default '',created_at bigint not null default (extract(epoch from now())*1000)::bigint
);
create table public.settings(key text primary key,value jsonb not null);
create table public.orders(
 id text primary key,request_id text not null unique,access_token text not null,user_id uuid references auth.users(id) on delete set null,
 name text not null,email text not null,phone text not null,address text not null,city text not null,state text not null,pin text not null,note text not null default '',items jsonb not null check(jsonb_typeof(items)='array'),
 subtotal integer not null check(subtotal>=0),discount integer not null check(discount>=0),shipping integer not null check(shipping>=0),total integer not null check(total=subtotal-discount+shipping),coupon text not null default '',
 status text not null default 'New' check(status in('New','Confirmed','Packing','Shipped','Delivered','Cancelled')),payment text not null check(payment in('Pending','Received','Preview','Refund required')),payment_method text not null check(payment_method in('preview','cod','razorpay')),gateway_order text unique,gateway_payment text,gateway_claimed_at timestamptz,tracking text not null default '',created_at bigint not null default (extract(epoch from now())*1000)::bigint
);
create index orders_user_created on public.orders(user_id,created_at desc);
create table public.subscribers(email text primary key,created_at timestamptz not null default now());
alter table public.admin_members enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.settings enable row level security;
alter table public.subscribers enable row level security;
create function public.is_shop_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.admin_members where user_id=(select auth.uid())); $$;
revoke all on function public.is_shop_admin() from public;
grant execute on function public.is_shop_admin() to anon,authenticated,service_role;
-- Browsers can never self-grant administrator membership.
create policy own_admin_membership on public.admin_members for select to authenticated using(user_id=(select auth.uid()));
create policy visible_catalog on public.products for select to anon,authenticated using(visible=1 or public.is_shop_admin());
create policy owner_products on public.products for all to authenticated using(public.is_shop_admin()) with check(public.is_shop_admin());
create policy store_settings_read on public.settings for select to anon,authenticated using(key='store');
create policy owner_settings on public.settings for all to authenticated using(public.is_shop_admin()) with check(public.is_shop_admin());
-- Orders contain private tracking keys and customer details. All reads/writes go through the authorised server.
revoke all on public.orders,public.subscribers,public.products,public.settings,public.admin_members from anon,authenticated;
grant select on public.admin_members to authenticated;
grant select on public.products,public.settings to anon,authenticated;
grant insert,update,delete on public.products,public.settings to authenticated;
grant all on public.products,public.orders,public.admin_members,public.settings,public.subscribers to service_role;

create function public.create_checkout_order(p_request_id text,p_token text,p_user_id uuid,p_customer jsonb,p_items jsonb,p_coupon text,p_method text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;p public.products%rowtype;item jsonb;s jsonb;line_items jsonb:='[]';sub integer:=0;disc integer:=0;delivery integer:=0;qty integer;offer text:='';
begin
 if length(p_request_id) not between 20 and 80 or length(p_token) not between 30 and 80 then raise exception 'Invalid checkout request';end if;
 -- Serialize retries before checking existence, then lock product rows in consistent ID order.
 perform pg_advisory_xact_lock(hashtextextended(p_request_id,0));
 select * into o from public.orders where request_id=p_request_id;
 if found then if o.access_token<>p_token then raise exception 'Invalid checkout key';end if;if o.status='Cancelled' then raise exception 'This order was cancelled. Start a new checkout';end if;return to_jsonb(o)-'access_token'-'request_id';end if;
 if p_method not in('preview','cod','razorpay') then raise exception 'Invalid payment method';end if;
 if coalesce(length(trim(p_customer->>'name')),0)<2 or coalesce(p_customer->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or coalesce(p_customer->>'phone','') !~ '^[6-9][0-9]{9}$' or coalesce(length(trim(p_customer->>'address')),0)<8 or coalesce(length(trim(p_customer->>'city')),0)<2 or coalesce(length(trim(p_customer->>'state')),0)<2 or coalesce(p_customer->>'pin','') !~ '^[1-9][0-9]{5}$' then raise exception 'Check customer contact and delivery address';end if;
 if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Invalid checkout items';end if;
 if jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Add between 1 and 30 items';end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_items) x)<>jsonb_array_length(p_items) then raise exception 'Duplicate checkout items';end if;
 select value into s from public.settings where key='store';if s is null then raise exception 'Store settings missing';end if;
 if p_method<>'preview' and (coalesce(s->>'email','')='' or coalesce(s->>'whatsapp','')='') then raise exception 'Store is completing checkout setup';end if;
 for item in select x from jsonb_array_elements(p_items) x order by x->>'id' loop
  if coalesce(item->>'quantity','') !~ '^[1-9][0-9]?$' then raise exception 'Enter a whole quantity between 1 and 99';end if;qty:=(item->>'quantity')::integer;
  select * into p from public.products where id=item->>'id' for update;
  if not found or p.visible<>1 then raise exception 'An item is no longer available';end if;
  if p.stock<qty then raise exception '%: only % available',p.name,p.stock;end if;
  if p_method<>'preview' and p.sample=1 then raise exception 'Sample products cannot be purchased';end if;
  sub:=sub+p.price*qty;
  line_items:=line_items||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'price',p.price,'quantity',qty,'image',p.image,'imagePosition',p.image_position,'size',p.size));
  update public.products set stock=stock-qty where id=p.id;
 end loop;
 if coalesce(trim(p_coupon),'')<>'' then
  if coalesce(s->>'couponCode','')='' or upper(trim(p_coupon))<>upper(s->>'couponCode') then raise exception 'Offer code is not valid';end if;
  offer:=s->>'couponCode';disc:=round(sub*(s->>'couponPercent')::numeric/100)::integer;
 end if;
 delivery:=case when sub-disc >= (s->>'freeShipping')::integer then 0 else (s->>'shipping')::integer end;
 insert into public.orders(id,request_id,access_token,user_id,name,email,phone,address,city,state,pin,note,items,subtotal,discount,shipping,total,coupon,status,payment,payment_method)
 values('EN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),p_request_id,p_token,p_user_id,left(trim(p_customer->>'name'),100),left(lower(p_customer->>'email'),254),p_customer->>'phone',left(p_customer->>'address',500),left(p_customer->>'city',80),left(p_customer->>'state',80),p_customer->>'pin',left(coalesce(p_customer->>'note',''),1000),line_items,sub,disc,delivery,sub-disc+delivery,offer,'New',case when p_method='preview' then 'Preview' else 'Pending' end,p_method) returning * into o;
 return to_jsonb(o)-'access_token'-'request_id';
end;$$;
create function public.claim_gateway_order(p_id text,p_token text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 update public.orders set gateway_claimed_at=now() where id=p_id and access_token=p_token and payment_method='razorpay' and status='New' and gateway_order is null and (gateway_claimed_at is null or gateway_claimed_at<now()-interval '2 minutes');return found;
end;$$;
create function public.manage_store_order(p_id text,p_status text,p_payment text,p_tracking text) returns void language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;item jsonb;
begin
 select * into o from public.orders where id=p_id for update;if not found then raise exception 'Order not found';end if;
 if p_status not in('New','Confirmed','Packing','Shipped','Delivered','Cancelled') or p_payment not in('Pending','Received','Preview','Refund required') then raise exception 'Invalid order status';end if;
 if o.status='Cancelled' and p_status<>'Cancelled' then raise exception 'Cancelled orders cannot be reopened';end if;
 if o.payment_method='razorpay' and p_payment<>o.payment then raise exception 'Online payment status requires gateway verification';end if;
 if o.payment_method='razorpay' and o.payment<>'Received' and p_status in('Confirmed','Packing','Shipped','Delivered') then raise exception 'Wait for verified payment before fulfilment';end if;
 if p_status='Cancelled' and o.status<>'Cancelled' then
  for item in select x from jsonb_array_elements(o.items) x order by x->>'id' loop update public.products set stock=stock+(item->>'quantity')::integer where id=item->>'id';end loop;
 end if;
 update public.orders set status=p_status,payment=case when p_status='Cancelled' and o.payment in('Received','Refund required') then 'Refund required' else p_payment end,tracking=left(coalesce(p_tracking,''),250) where id=p_id;
end;$$;
create function public.record_captured_payment(p_gateway_order text,p_payment text,p_amount integer,p_currency text) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.orders set payment=case when status='Cancelled' then 'Refund required' else 'Received' end,status=case when status='New' then 'Confirmed' else status end,gateway_payment=p_payment where gateway_order=p_gateway_order and total=p_amount and p_currency='INR' and payment_method='razorpay';
end;$$;
-- Checkout and payment mutations are server-only; anon/authenticated cannot call them directly.
revoke all on function public.create_checkout_order(text,text,uuid,jsonb,jsonb,text,text),public.claim_gateway_order(text,text),public.manage_store_order(text,text,text,text),public.record_captured_payment(text,text,integer,text) from public,anon,authenticated;
grant execute on function public.create_checkout_order(text,text,uuid,jsonb,jsonb,text,text),public.claim_gateway_order(text,text),public.manage_store_order(text,text,text,text),public.record_captured_payment(text,text,integer,text) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('product-images','product-images',true,5000000,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy owner_product_images_insert on storage.objects for insert to authenticated with check(bucket_id='product-images' and public.is_shop_admin());
create policy owner_product_images_update on storage.objects for update to authenticated using(bucket_id='product-images' and public.is_shop_admin()) with check(bucket_id='product-images' and public.is_shop_admin());
create policy owner_product_images_delete on storage.objects for delete to authenticated using(bucket_id='product-images' and public.is_shop_admin());
create policy owner_product_images_read on storage.objects for select to authenticated using(bucket_id='product-images' and public.is_shop_admin());
insert into public.settings(key,value) values('store','{"brand":"ENWAKE","tagline":"Candles & quiet rituals","shipping":9900,"freeShipping":149900,"whatsapp":"","email":"","instagram":"","couponCode":"WELCOME10","couponPercent":10,"policyShipping":"Shipping timelines will be confirmed by the store before launch.","policyReturns":"Contact the store about damaged or incorrect items. Final return terms will be published before launch."}'::jsonb);
commit;
