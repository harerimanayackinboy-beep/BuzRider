create or replace function find_candidate_drivers(
  p_pickup geography, p_vehicle vehicle_type, p_weight numeric, p_radius_m int default 10000, p_limit int default 3
) returns table (driver_id uuid, vehicle_id uuid, distance_m double precision)
language sql stable security invoker set search_path = public as $$
  select dp.id, v.id, st_distance(dl.location, p_pickup)
  from driver_profiles dp
  join vehicles v on v.driver_id = dp.id and v.is_active and v.type = p_vehicle
       and (p_weight is null or v.max_load_kg is null or v.max_load_kg >= p_weight)
  join driver_locations dl on dl.driver_id = dp.id
  where dp.is_online and dp.verification_status = 'approved'
    and dl.updated_at > now() - interval '5 minutes'
    and st_dwithin(dl.location, p_pickup, p_radius_m)
    and not exists (select 1 from deliveries d where d.driver_id = dp.id
                    and d.status in ('driver_assigned','driver_arriving','picked_up','in_transit'))
  order by st_distance(dl.location, p_pickup)
  limit p_limit;
$$;
revoke execute on function find_candidate_drivers(geography, vehicle_type, numeric, int, int) from public, anon, authenticated;
grant execute on function find_candidate_drivers(geography, vehicle_type, numeric, int, int) to service_role;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
alter function public.set_updated_at() set search_path = public;
