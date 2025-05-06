-- Supabase Function and Trigger for Trust Score Calculation (Updated with Sentiment)

-- 1. Update the function to calculate and update the trust score, including sentiment.
create or replace function public.calculate_trust_score(p_user_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_score integer := 0;
  v_id_verified boolean := false;
  v_cpr_verified boolean := false;
  v_insurance_verified boolean := false;
  v_avg_sentiment_score numeric := 0;
  v_review_count integer := 0;
  v_sentiment_contribution integer := 0;
  v_score_breakdown jsonb := 
'{}
';
  v_tier text;
begin
  -- Check verified documents
  select exists(select 1 from documents where user_id = p_user_id and document_type = 
'ID
' and verification_status = 
'Verified
') into v_id_verified;
  select exists(select 1 from documents where user_id = p_user_id and document_type = 
'CPR
' and verification_status = 
'Verified
') into v_cpr_verified;
  select exists(select 1 from documents where user_id = p_user_id and document_type = 
'Insurance
' and verification_status = 
'Verified
') into v_insurance_verified;

  -- Calculate score based on verifications
  if v_id_verified then
    v_score := v_score + 20;
    v_score_breakdown := v_score_breakdown || 
'{"id_verified": 20}
';
  else
     v_score_breakdown := v_score_breakdown || 
'{"id_verified": 0}
';
  end if;

  if v_cpr_verified then
    v_score := v_score + 15;
     v_score_breakdown := v_score_breakdown || 
'{"cpr_verified": 15}
';
  else
     v_score_breakdown := v_score_breakdown || 
'{"cpr_verified": 0}
';
  end if;

  if v_insurance_verified then
    v_score := v_score + 15;
     v_score_breakdown := v_score_breakdown || 
'{"insurance_verified": 15}
';
  else
      v_score_breakdown := v_score_breakdown || 
'{"insurance_verified": 0}
';
  end if;

  -- Calculate Review Sentiment Score Contribution (max 30)
  -- Fetch average sentiment score (assuming scores are -1, 0, 1)
  select avg(sentiment_score), count(*)
  into v_avg_sentiment_score, v_review_count
  from public.reviews
  where user_id = p_user_id and sentiment_score is not null;

  if v_review_count > 0 then
    -- Scale the average sentiment (-1 to 1) to a 0-30 point range.
    -- Example scaling: (avg_sentiment + 1) * 15
    -- This maps -1 to 0 points, 0 to 15 points, 1 to 30 points.
    v_sentiment_contribution := round((coalesce(v_avg_sentiment_score, 0) + 1) * 15);
    v_score := v_score + v_sentiment_contribution;
  else
    v_sentiment_contribution := 0; -- No reviews, no sentiment points
  end if;
  v_score_breakdown := v_score_breakdown || jsonb_build_object(
'review_sentiment
', v_sentiment_contribution);


  -- Placeholder for Badge Usage / Profile Completeness (max 20) - Add logic later
  -- For now, let's give 20 points if all 3 docs are verified as a proxy
  if v_id_verified and v_cpr_verified and v_insurance_verified then
     v_score := v_score + 20;
     v_score_breakdown := v_score_breakdown || 
'{"profile_completeness": 20}
';
  else
     v_score_breakdown := v_score_breakdown || 
'{"profile_completeness": 0}
';
  end if;

  -- Ensure score does not exceed 100
  v_score := least(v_score, 100);
  -- Ensure score is not negative (though unlikely with current logic)
  v_score := greatest(v_score, 0);

  -- Determine Tier
  if v_score >= 75 then
    v_tier := 
'Gold
';
  elsif v_score >= 40 then
    v_tier := 
'Silver
';
  else
    v_tier := 
'Bronze
';
  end if;

  -- Insert or update the trust_scores table
  insert into public.trust_scores (user_id, score, score_breakdown, tier, last_calculated_at)
  values (p_user_id, v_score, v_score_breakdown, v_tier, timezone(
'utc
', now()))
  on conflict (user_id)
  do update set
    score = excluded.score,
    score_breakdown = excluded.score_breakdown,
    tier = excluded.tier,
    last_calculated_at = excluded.last_calculated_at;

end;
$$;

-- 2. Update the trigger function for document changes (no change needed here, it already calls calculate_trust_score)
-- create or replace function public.handle_document_update() ... (remains the same)

-- 3. Create a NEW trigger function to recalculate score when reviews change.
create or replace function public.handle_review_score_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid;
begin
  -- Determine user_id from the changed row (either OLD or NEW)
  if tg_op = 
'DELETE
' then
    v_user_id := old.user_id;
  else
    v_user_id := new.user_id;
  end if;

  -- Recalculate score if sentiment score changed or a review was added/deleted
  if tg_op = 
'INSERT
' or tg_op = 
'DELETE
' or (tg_op = 
'UPDATE
' and new.sentiment_score is distinct from old.sentiment_score) then
     perform public.calculate_trust_score(v_user_id);
  end if;

  -- Return the appropriate value for the trigger type
  if tg_op = 
'DELETE
' then
    return old;
  else
    return new;
  end if;
end;
$$;

-- 4. Create the trigger on the reviews table to call the score recalculation.
drop trigger if exists on_review_change_recalculate_score on public.reviews; -- Drop existing trigger
create trigger on_review_change_recalculate_score
  after insert or update or delete on public.reviews
  for each row execute procedure public.handle_review_score_update();

-- Note: Ensure these functions/triggers are created by a superuser or with appropriate permissions.
-- You need to run this SQL in your Supabase project's SQL Editor.
-- This REPLACES the previous trust score function and adds a new trigger on the reviews table.

