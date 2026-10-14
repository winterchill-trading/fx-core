Rates from the simulated source on a Friday:

  $ fx-core rates -now 2026-10-09T12:00:00Z
  AUD  1.52654        2026-10-09 live
  CAD  1.36163        2026-10-09 live
  CHF  0.88           2026-10-09 live
  EUR  0.922024       2026-10-09 live
  GBP  0.790474       2026-10-09 live
  JPY  149.925        2026-10-09 live
  NOK  10.6529        2026-10-09 live
  PLN  3.94763        2026-10-09 live
  SEK  10.5021        2026-10-09 live

A quote selling a fixed amount, with a tier cap on the spread:

  $ fx-core quote EUR GBP -sell 100.00 -cap 35 -now 2026-10-09T12:00:00Z
  ((id cli) (sell "100.00 EUR") (buy "85.43 GBP") (fee "0.35 EUR")
   (fixed_side Sell) (mid_rate 0.85732475510398861635)
   (inverse_mid_rate 1.1664191358602559983) (customer_rate 0.8543241184)
   (inverse_customer_rate 1.170515942)
   (spread ((standard_bps 50) (applied_bps 35)))
   (basis
    ((source simulated) (origin Live) (rate_date 2026-10-09)
     (fetched_at "2026-10-09 12:00:00Z")))
   (stale false) (created_at "2026-10-09 12:00:00Z")
   (expires_at "2026-10-09 12:00:30Z"))

Buying a fixed amount of yen:

  $ fx-core quote EUR JPY -buy 10000 -now 2026-10-09T12:00:00Z
  ((id cli) (sell "61.81 EUR") (buy "10000 JPY") (fee "0.31 EUR")
   (fixed_side Buy) (mid_rate 162.60422722185105811)
   (inverse_mid_rate 0.0061499016174754043689) (customer_rate 161.791206)
   (inverse_customer_rate 0.006180805649)
   (spread ((standard_bps 50) (applied_bps 50)))
   (basis
    ((source simulated) (origin Live) (rate_date 2026-10-09)
     (fetched_at "2026-10-09 12:00:00Z")))
   (stale false) (created_at "2026-10-09 12:00:00Z")
   (expires_at "2026-10-09 12:00:30Z"))

Refusals carry a reason:

  $ fx-core quote EUR EUR -sell 1.00 -now 2026-10-09T12:00:00Z
  (Same_currency EUR)
  [1]

Offline mode: a bundled table from October still prices in November, marked stale.

  $ fx-core bundle -from 2026-10-08 -to 2026-10-09 > rates.csv
  $ head -3 rates.csv
  date,currency,rate
  2026-10-08,AUD,1.52182
  2026-10-08,CAD,1.35592
  $ fx-core quote GBP CHF -sell 50.00 -bundled rates.csv -now 2026-11-20T09:00:00Z
  ((id cli) (sell "50.00 GBP") (buy "55.38 CHF") (fee "0.25 GBP")
   (fixed_side Sell) (mid_rate 1.1132560969747265565)
   (inverse_mid_rate 0.89826590909090909091) (customer_rate 1.107689816)
   (inverse_customer_rate 0.9027798085)
   (spread ((standard_bps 50) (applied_bps 50)))
   (basis
    ((source bundled) (origin Bundled) (rate_date 2026-10-09)
     (fetched_at "2026-10-09 00:00:00Z")))
   (stale true) (created_at "2026-11-20 09:00:00Z")
   (expires_at "2026-11-20 09:00:30Z"))
