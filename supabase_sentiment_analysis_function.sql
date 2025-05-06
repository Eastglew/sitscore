-- Supabase Function for Keyword-Based Sentiment Analysis

-- 1. Create the function to analyze review text and return a score (-1, 0, 1 or scaled).
create or replace function public.analyze_review_sentiment(review_text text)
returns integer
language plpgsql
as $$
declare
  positive_keywords text[] := array[
    -- General Positive
    'great', 'excellent', 'amazing', 'wonderful', 'fantastic', 'perfect', 'loved', 'happy', 'satisfied', 'reliable', 'trustworthy', 'professional', 'caring', 'attentive', 'responsive',
    -- Pet Specific Positive
    'good with my dog', 'good with my cat', 'handled well', 'followed instructions', 'sent updates', 'sent photos', 'playful', 'energetic', 'calm'
  ];
  negative_keywords text[] := array[
    -- General Negative
    'bad', 'terrible', 'awful', 'horrible', 'disappointed', 'unhappy', 'unreliable', 'unprofessional', 'late', 'no show', 'cancelled', 'cancel', 'issue', 'problem', 'complaint', 'poor',
    -- Pet Specific Negative
    'scared my pet', 'did not follow instructions', 'ignored', 'messy', 'house dirty', 'accident', 'lost', 'injury', 'emergency'
  ];
  word text;
  positive_score integer := 0;
  negative_score integer := 0;
  normalized_text text;
begin
  -- Basic normalization: lowercase and remove punctuation (simple version)
  normalized_text := lower(regexp_replace(review_text, '[^\w\s]', '', 'g'));

  -- Check for positive keywords
  foreach word in array positive_keywords
  loop
    if normalized_text like '%' || word || '%' then
      positive_score := positive_score + 1;
    end if;
  end loop;

  -- Check for negative keywords
  foreach word in array negative_keywords
  loop
    if normalized_text like '%' || word || '%' then
      negative_score := negative_score + 1;
    end if;
  end loop;

  -- Simple scoring logic: return 1 for positive, -1 for negative, 0 for neutral/mixed
  -- More sophisticated scoring could weigh keywords or consider intensity
  if positive_score > negative_score then
    return 1; -- Positive
  elsif negative_score > positive_score then
    return -1; -- Negative
  else
    return 0; -- Neutral or Mixed
  end if;

  -- Alternative: Return a scaled score (e.g., based on net count)
  -- return positive_score - negative_score;

end;
$$;

-- 2. Create a trigger function to update sentiment score on insert/update.
create or replace function public.handle_review_sentiment_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_sentiment_score integer;
begin
  -- Only calculate if review_text is provided and changed (or on insert)
  if new.review_text is not null and (tg_op = 'INSERT' or new.review_text is distinct from old.review_text) then
    v_sentiment_score := public.analyze_review_sentiment(new.review_text);
    new.sentiment_score := v_sentiment_score;
  end if;

  return new;
end;
$$;

-- 3. Create the trigger on the reviews table.
drop trigger if exists on_review_change_update_sentiment on public.reviews; -- Drop existing trigger
create trigger on_review_change_update_sentiment
  before insert or update on public.reviews
  for each row execute procedure public.handle_review_sentiment_update();

-- Note: Ensure these functions/triggers are created by a superuser or with appropriate permissions.
-- You need to run this SQL in your Supabase project's SQL Editor.

