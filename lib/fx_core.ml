(** Foreign exchange for banks.

    {ul
     {- Rates: {!Observation}, {!Origin}, {!Rate_table} (as-of lookup, cross rates
        through a pivot), {!Basis}, {!Freshness} (stale, too old, offline mode).}
     {- Pricing: {!Spread} (caps and tiers), {!Pricing} (customer rate, directional
        rounding, included fee), {!Card_fx}, {!Valuation}.}
     {- Quotes and execution: {!Quote}, {!Quote_book} (open, executed, expired),
        {!Exchange} (ledger entries through payments-core).}
     {- Sources: {!Rate_source}, {!Simulated_source}, {!Bundled}, {!Refresh}.}
     {- Shared: {!Ratio} (exact rationals), {!Refusal} (why something was refused).}} *)

module Ratio = Ratio
module Origin = Origin
module Observation = Observation
module Basis = Basis
module Refusal = Refusal
module Freshness = Freshness
module Rate_table = Rate_table
module Spread = Spread
module Pricing = Pricing
module Quote = Quote
module Quote_book = Quote_book
module Exchange = Exchange
module Card_fx = Card_fx
module Valuation = Valuation
module Rate_source = Rate_source
module Simulated_source = Simulated_source
module Bundled = Bundled
module Refresh = Refresh
