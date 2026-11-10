# CFA Level III — all 36 readings, for scheduling

## How to read the columns — IMPORTANT, one column was retired

A previous sweep used a single `calc%` column taken from the question bank's
`needs_calculator` flag. That column was CONFOUNDED and must not be reconstructed:
every one of the bank's 227 essay questions is flagged `needs_calculator = true`,
so `calc%` was essay-share plus some multiple choice, not a measure of arithmetic.
It correlated r = +0.77 with essay share. Ratings that leaned on it were really
leaning on essay share twice.

It is replaced by three independent columns:

- `essay%`  — share of this reading's BANK questions that are constructed-response.
              Honest, and the best single proxy for "needs a desk to answer properly".
- `mcCalc%` — of this reading's MULTIPLE-CHOICE bank questions only, the share
              flagged as needing a calculator. Uncounfounded, because within MC the
              flag genuinely splits (184 true / 86 false across the bank).
- `drlCalc%`— of this reading's LOS DRILLS (a separate 2,667-question set, all
              multiple choice), the share needing a calculator. Fully independent
              of the bank. Note these run LOW everywhere (1-12%).
- `phoneQ`  — how many of this reading's drills are answerable on a phone with no
              calculator. Across all 36 readings 2,584 of 2,667 drills qualify, so
              this number is HIGH almost everywhere. Do not read a high `phoneQ` as
              evidence that a tired phone review is worthwhile — it only means the
              material is technically answerable. Judging whether it is WORTHWHILE
              is exactly what the second score below is for.

Where a column is '-', there were no questions of that kind for this reading.


---

## Principles of Asset Allocation

`reading_id: principles_of_asset_allocation`  —  Book 1 (Asset Allocation), 17.5% of the exam

- bank: 33 questions, 13 essays across 6 cases
- essay% 39 · mcCalc% 100 · drlCalc% 5 · phoneQ 71 of 75 drills
- LOS command verbs: describe x5, recommend x4, discuss x4, interpret x1, explain x1

  Learning outcome statements (15):
  - describe and evaluate the use of mean–variance optimization in asset allocation
  - recommend and justify an asset allocation using mean–variance optimization
  - interpret and evaluate an asset allocation in relation to an investor's economic balance sheet
  - recommend and justify an asset allocation based on the global market portfolio
  - discuss the use of Monte Carlo simulation and scenario analysis to evaluate the robustness of an asset allocation
  - discuss asset class liquidity considerations in asset allocation
  - explain absolute and relative risk budgets and their use in determining and implementing an asset allocation
  - describe how client needs and preferences regarding investment risks can be incorporated into asset allocation
  - describe the use of investment factors in constructing and analyzing an asset allocation
  - describe and evaluate characteristics of liabilities that are relevant to asset allocation
  - discuss approaches to liability-relative asset allocation
  - recommend and justify a liability-relative asset allocation
  - recommend and justify an asset allocation using a goals-based approach
  - describe and evaluate heuristic and other approaches to asset allocation
  - discuss factors affecting rebalancing policy

---

## Capital Market Expectations, Part 2: Forecasting Asset Class Returns

`reading_id: capital_market_expectations_part_2_forecasting_asset_class_returns`  —  Book 1 (Asset Allocation), 17.5% of the exam

- bank: 9 questions, 5 essays across 2 cases
- essay% 56 · mcCalc% 100 · drlCalc% 9 · phoneQ 68 of 75 drills
- LOS command verbs: discuss x6, explain x1, recommend x1

  Learning outcome statements (8):
  - discuss approaches to setting expectations for fixed-income returns
  - discuss risks faced by investors in emerging market fixed-income securities and the country risk analysis techniques used to evaluate emerging market economies
  - discuss approaches to setting expectations for equity investment market returns
  - discuss risks faced by investors in emerging market equity securities
  - explain how economic and competitive factors can affect expectations for real estate investment markets and sector returns
  - discuss major approaches to forecasting exchange rates
  - discuss methods of forecasting volatility
  - recommend and justify changes in the component weights of a global investment portfolio based on trends and expected changes in macroeconomic factors

---

## Overview of Asset Allocation

`reading_id: overview_of_asset_allocation`  —  Book 1 (Asset Allocation), 17.5% of the exam

- bank: 29 questions, 12 essays across 6 cases
- essay% 41 · mcCalc% 100 · drlCalc% 1 · phoneQ 74 of 75 drills
- LOS command verbs: describe x2, explain x2, discuss x2, formulate x1, compare x1, contrast x1

  Learning outcome statements (10):
  - describe elements of effective investment governance and investment governance considerations in asset allocation
  - formulate an economic balance sheet for a client and interpret its implications for asset allocation
  - compare the investment objectives of asset-only, liability-relative, and goals-based asset allocation approaches
  - contrast concepts of risk relevant to asset-only, liability-relative, and goals-based asset allocation approaches
  - explain how asset classes are used to represent exposures to systematic risk and discuss criteria for asset class specification
  - explain the use of risk factors in asset allocation and their relation to traditional asset class–based approaches
  - recommend and justify an asset allocation based on an investor's objectives and constraints
  - describe the use of the global market portfolio as a baseline portfolio in asset allocation
  - discuss strategic implementation choices in asset allocation, including passive/active choices and vehicles for implementing passive and active mandates
  - discuss strategic considerations in rebalancing asset allocations

---

## Asset Allocation with Real-World Constraints

`reading_id: asset_allocation_with_real_world_constraints`  —  Book 1 (Asset Allocation), 17.5% of the exam

- bank: 10 questions, 3 essays across 2 cases
- essay% 30 · mcCalc% 100 · drlCalc% 1 · phoneQ 74 of 75 drills
- LOS command verbs: discuss x3, recommend x1, identify x1

  Learning outcome statements (5):
  - discuss asset size, liquidity needs, time horizon, and regulatory or other considerations as constraints on asset allocation
  - discuss tax considerations in asset allocation and rebalancing
  - recommend and justify revisions to an asset allocation given change(s) in investment objectives and/or constraints
  - discuss the use of short-term shifts in asset allocation
  - identify behavioral biases that arise in asset allocation and recommend methods to overcome them

---

## Capital Market Expectations, Part 1: Framework and Macro Considerations

`reading_id: capital_market_expectations_part_1_framework_and_macro_considerations`  —  Book 1 (Asset Allocation), 17.5% of the exam

- bank: 38 questions, 18 essays across 6 cases
- essay% 47 · mcCalc% 65 · drlCalc% 3 · phoneQ 73 of 75 drills
- LOS command verbs: discuss x5, explain x2, compare x1, interpret x1, identify x1

  Learning outcome statements (10):
  - discuss the role of, and a framework for, capital market expectations in the portfolio management process
  - discuss challenges in developing capital market forecasts
  - explain how exogenous shocks may affect economic growth trends
  - discuss the application of economic growth trend analysis to the formulation of capital market expectations
  - compare major approaches to economic forecasting
  - discuss how business cycles affect short- and long-term expectations
  - explain the relationship of inflation to the business cycle and the implications of inflation for cash, bonds, equity, and real estate returns
  - discuss the effects of monetary and fiscal policy on business cycles
  - interpret the shape of the yield curve as an economic predictor and discuss the relationship between the yield curve and fiscal and monetary policy
  - identify and interpret macroeconomic, interest rate, and exchange rate linkages between economies

---

## An Overview of Private Wealth Management

`reading_id: an_overview_of_private_wealth_management`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 6 questions, 5 essays across 3 cases
- essay% 83 · mcCalc% 100 · drlCalc% 9 · phoneQ 79 of 87 drills
- LOS command verbs: discuss x2, evaluate x2, justify x1

  Learning outcome statements (5):
  - discuss the different types of individual wealth and how wealth is created and distributed globally
  - evaluate how changes in human capital, financial capital, and economic net worth across the financial stages of an individual's life influence their financial decision making
  - justify how returns, risks, objectives, and constraints for individuals relate to their human and financial capital
  - evaluate how various types of taxes imposed on individual investors and the impact of inflation influence investment decisions
  - discuss the differences between private and institutional clients and formulate an appropriate Investment Policy Statement for private clients

---

## Asset Allocation to Alternative Investments

`reading_id: asset_allocation_to_alternative_investments`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 27 questions, 15 essays across 4 cases
- essay% 56 · mcCalc% 0 · drlCalc% 0 · phoneQ 81 of 81 drills
- LOS command verbs: discuss x5, compare x2, explain x1

  Learning outcome statements (8):
  - explain the roles that alternative investments play in multi-asset portfolios
  - compare alternative investments and bonds as risk mitigators in relation to a long equity position
  - compare traditional and risk-based approaches to defining the investment opportunity set, including alternative investments
  - discuss investment considerations that are important in allocating to different types of alternative investments
  - discuss suitability considerations in allocating to alternative investments
  - discuss approaches to asset allocation to alternative investments
  - discuss the importance of liquidity planning in allocating to alternative investments
  - discuss considerations in monitoring alternative investment programs

---

## Portfolio Management for Institutional Investors

`reading_id: portfolio_management_for_institutional_investors`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 24 questions, 12 essays across 3 cases
- essay% 50 · mcCalc% 50 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: discuss x3, evaluate x3, describe x2

  Learning outcome statements (8):
  - discuss common characteristics of institutional investors as a group
  - discuss investment policy of institutional investors
  - discuss the stakeholders in the portfolio, the liabilities, the investment time horizons, and the liquidity needs of different types of institutional investors
  - describe the focus of legal, regulatory, and tax constraints affecting different types of institutional investors
  - evaluate risk considerations of private defined benefit (DB) pension plans in relation to 1) plan funded status, 2) sponsor financial strength, 3) interactions between the sponsor's business and the fund's investments, 4) plan design, and 5) workforce characteristics
  - evaluate the investment policy statement of an institutional investor
  - evaluate the investment portfolio of a private DB plan, sovereign wealth fund, university endowment, and private foundation
  - describe considerations affecting the balance sheet management of banks and insurers

---

## Case Study in Portfolio Management: Institutional (SWF)

`reading_id: case_study_in_portfolio_management_institutional_swf`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 5 questions, 3 essays across 1 cases
- essay% 60 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: discuss x3, analyze x1, evaluate x1

  Learning outcome statements (5):
  - discuss financial risks associated with the portfolio strategy of an institutional investor
  - discuss environmental and social risks associated with the portfolio strategy of an institutional investor
  - analyze and evaluate the financial and non-financial risk exposures in the portfolio strategy of an institutional investor
  - discuss various methods to manage the risks that arise on long-term direct investments of an institutional investor
  - evaluate strengths and weaknesses of an enterprise risk management system and recommend improvements

---

## Overview of Fixed-Income Portfolio Management

`reading_id: overview_of_fixed_income_portfolio_management`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 13 questions, 6 essays across 4 cases
- essay% 46 · mcCalc% 100 · drlCalc% 8 · phoneQ 69 of 75 drills
- LOS command verbs: describe x6, discuss x3

  Learning outcome statements (9):
  - discuss roles of fixed-income securities in portfolios and how fixed-income mandates may be classified
  - describe fixed-income portfolio measures of risk and return as well as correlation characteristics
  - describe bond market liquidity, including the differences among market sub-sectors, and discuss the effect of liquidity on fixed-income portfolio management
  - describe and interpret a model for fixed-income returns
  - discuss the use of leverage, alternative methods for leveraging, and risks that leverage creates in fixed-income portfolios
  - discuss differences in managing fixed-income portfolios for taxable and tax-exempt investors
  - describe liability-driven investing
  - describe the strategy of cash flow matching
  - describe construction, benefits, limitations, and risk–return characteristics of a laddered bond portfolio

---

## Trading Costs and Electronic Markets

`reading_id: trading_costs_and_electronic_markets`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 3 questions, 3 essays across 1 cases
- essay% 100 · mcCalc% - · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: describe x7, explain x1, calculate x1, identify x1

  Learning outcome statements (10):
  - explain the components of execution costs, including explicit and implicit costs
  - calculate and interpret effective spreads and VWAP transaction cost estimates
  - describe the implementation shortfall approach to transaction cost measurement
  - describe factors driving the development of electronic trading systems
  - describe market fragmentation
  - identify and contrast the types of electronic traders
  - describe characteristics and uses of electronic trading systems
  - describe comparative advantages of low-latency traders
  - describe the risks associated with electronic trading and how regulators mitigate them
  - describe abusive trading practices that real-time surveillance of markets may detect

---

## Overview of Equity Portfolio Management

`reading_id: overview_of_equity_portfolio_management`  —  Book 2 (Portfolio Construction), 17.5% of the exam

- bank: 2 questions, 2 essays across 2 cases
- essay% 100 · mcCalc% - · drlCalc% 4 · phoneQ 72 of 75 drills
- LOS command verbs: describe x5, discuss x1

  Learning outcome statements (6):
  - describe the roles of equities in the overall portfolio
  - describe how an equity manager's investment universe can be segmented
  - describe the types of income and costs associated with owning and managing an equity portfolio and their potential effects on portfolio performance
  - describe the potential benefits of shareholder engagement and the role an equity manager might play in shareholder engagement
  - describe rationales for equity investment across the active management spectrum
  - discuss considerations in choosing a benchmark for an equity portfolio

---

## Portfolio Performance Evaluation

`reading_id: portfolio_performance_evaluation`  —  Book 3 (Performance Measurement), 7.5% of the exam

- bank: 22 questions, 8 essays across 2 cases
- essay% 36 · mcCalc% 57 · drlCalc% 12 · phoneQ 66 of 75 drills
- LOS command verbs: describe x6, discuss x3, interpret x2, explain x1, contrast x1, identify x1

  Learning outcome statements (16):
  - explain the following components of portfolio evaluation and their interrelationships: performance measurement, performance attribution, and performance appraisal
  - describe attributes of an effective attribution process
  - contrast return attribution and risk attribution; contrast macro and micro return attribution
  - describe returns-based, holdings-based, and transactions-based performance attribution, including advantages and disadvantages of each
  - interpret the sources of portfolio returns using a specified attribution approach
  - interpret the output from fixed-income attribution analyses
  - discuss considerations in selecting a risk attribution approach
  - identify and interpret investment results attributable to the asset owner versus those attributable to the investment manager
  - discuss uses of liability-based benchmarks
  - describe types of asset-based benchmarks
  - discuss tests of benchmark quality
  - describe the impact of benchmark misspecification on attribution and appraisal analysis
  - describe problems that arise in benchmarking alternative investments
  - calculate and interpret the Sortino ratio, the appraisal ratio, upside/downside capture ratios, maximum drawdown, and drawdown duration
  - describe limitations of appraisal measures and related metrics
  - evaluate the skill of an investment manager

---

## Investment Manager Selection

`reading_id: investment_manager_selection`  —  Book 3 (Performance Measurement), 7.5% of the exam

- bank: 16 questions, 8 essays across 2 cases
- essay% 50 · mcCalc% 100 · drlCalc% 3 · phoneQ 73 of 75 drills
- LOS command verbs: describe x4, evaluate x2, contrast x1, discuss x1, compare x1, analyze x1

  Learning outcome statements (10):
  - describe the components of a manager selection process, including due diligence
  - contrast Type I and Type II errors in manager hiring and continuation decisions
  - describe uses of returns-based and holdings-based style analysis in investment manager selection
  - describe uses of the upside capture ratio, downside capture ratio, maximum drawdown, drawdown duration, and up/down capture in evaluating managers
  - evaluate a manager's investment philosophy and investment decision-making process
  - discuss how behavioral factors affect investment team decision making, and recommend techniques for mitigating their effects
  - evaluate the costs and benefits of pooled investment vehicles and separate accounts
  - compare types of investment manager contracts, including their major provisions and advantages and disadvantages
  - describe the three basic forms of performance-based fees
  - analyze and interpret a sample performance-based fee schedule

---

## Overview of the Global Investment Performance Standards

`reading_id: overview_of_the_global_investment_performance_standards`  —  Book 3 (Performance Measurement), 7.5% of the exam

- bank: 4 questions, 4 essays across 1 cases
- essay% 100 · mcCalc% - · drlCalc% 4 · phoneQ 72 of 75 drills
- LOS command verbs: explain x8, discuss x3

  Learning outcome statements (11):
  - discuss the objectives and scope of the GIPS standards and their benefits to prospective clients and investors, as well as investment managers
  - explain the fundamentals of compliance with the GIPS standards, including the definition of the firm and the firm's definition of discretion
  - discuss requirements of the GIPS standards with respect to return calculation methodologies, including the treatment of external cash flows, cash and cash equivalents, and expenses and fees
  - explain the recommended valuation hierarchy of the GIPS standards
  - explain requirements of the GIPS standards with respect to composite return calculations, including methods for asset-weighting portfolio returns
  - explain the meaning of "discretionary" in the context of composite construction and, given a description of the relevant facts, determine whether a portfolio is likely to be considered discretionary
  - explain the role of investment mandates, objectives, or strategies in the construction of composites
  - explain requirements of the GIPS standards with respect to composite construction, including switching portfolios among composites, the timing of the inclusion of new portfolios in composites, and the timing of the exclusion of terminated portfolios from composites
  - explain requirements of the GIPS standards with respect to presentation and reporting
  - explain the conditions under which the performance of a past firm or affiliation may be linked to or used to represent the historical performance of a new or acquiring firm
  - discuss the purpose, scope, and process of verification

---

## Options Strategies

`reading_id: options_strategies`  —  Book 4 (Derivatives & Risk Management), 12.5% of the exam

- bank: 26 questions, 17 essays across 6 cases
- essay% 65 · mcCalc% 100 · drlCalc% 7 · phoneQ 70 of 75 drills
- LOS command verbs: discuss x4, demonstrate x2, compare x2, describe x1, identify x1

  Learning outcome statements (10):
  - demonstrate how an asset's returns may be replicated by using options
  - discuss the investment objective(s), structure, payoff, risk(s), value at expiration, profit, maximum profit, maximum loss, and breakeven underlying price at expiration of a covered call position
  - discuss the investment objective(s), structure, payoff, risk(s), value at expiration, profit, maximum profit, maximum loss, and breakeven underlying price at expiration of a protective put position
  - compare the delta of covered call and protective put positions with the position of being long an asset and short a forward on the underlying asset
  - compare the effect of buying a call on a short underlying position with the effect of selling a put on a short underlying position
  - discuss the investment objective(s), structure, payoffs, risk(s), value at expiration, profit, maximum profit, maximum loss, and breakeven underlying price at expiration of the following option strategies: bull spread, bear spread, straddle, and collar
  - describe uses of calendar spreads
  - discuss volatility skew and smile
  - identify and evaluate appropriate option strategies consistent with given investment objectives
  - demonstrate the use of options to achieve targeted equity risk exposures

---

## Swaps, Forwards, and Futures Strategies

`reading_id: swaps_forwards_and_futures_strategies`  —  Book 4 (Derivatives & Risk Management), 12.5% of the exam

- bank: 17 questions, 10 essays across 3 cases
- essay% 59 · mcCalc% 71 · drlCalc% 3 · phoneQ 73 of 75 drills
- LOS command verbs: demonstrate x6

  Learning outcome statements (6):
  - demonstrate how interest rate swaps, forwards, and futures can be used to modify a portfolio's risk and return
  - demonstrate how currency swaps, forwards, and futures can be used to modify a portfolio's risk and return
  - demonstrate how equity swaps, forwards, and futures can be used to modify a portfolio's risk and return
  - demonstrate the use of volatility derivatives and variance swaps
  - demonstrate the use of derivatives to achieve targeted equity and interest rate risk exposures
  - demonstrate the use of derivatives in asset allocation, rebalancing, and inferring market expectations

---

## Currency Management: An Introduction

`reading_id: currency_management_an_introduction`  —  Book 4 (Derivatives & Risk Management), 12.5% of the exam

- bank: 26 questions, 14 essays across 4 cases
- essay% 54 · mcCalc% 100 · drlCalc% 4 · phoneQ 72 of 75 drills
- LOS command verbs: describe x4, discuss x2, analyze x1, formulate x1, compare x1

  Learning outcome statements (9):
  - analyze the effects of currency movements on portfolio risk and return
  - discuss strategic choices in currency management
  - formulate an appropriate currency management program given financial market conditions and portfolio objectives and constraints
  - compare active currency trading strategies based on economic fundamentals, technical analysis, carry-trade, and volatility trading
  - describe how changes in factors underlying active trading strategies affect tactical trading decisions
  - describe how forward contracts and FX (foreign exchange) swaps are used to adjust hedge ratios
  - describe trading strategies used to reduce hedging costs and modify the risk–return characteristics of a foreign-currency portfolio
  - describe the use of cross-hedges, macro-hedges, and minimum-variance-hedge ratios in portfolios exposed to multiple foreign currencies
  - discuss challenges for managing emerging market currency exposures

---

## Application of the Code and Standards: Level III

`reading_id: application_of_code_and_standards_l3`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 16 questions, 15 essays across 8 cases
- essay% 94 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: evaluate x1, explain x1

  Learning outcome statements (2):
  - evaluate practices, policies, and conduct relative to the CFA Institute Code of Ethics and Standards of Professional Conduct
  - explain how the practices, policies, or conduct does or does not violate the CFA Institute Code of Ethics and Standards of Professional Conduct

---

## Asset Manager Code of Professional Conduct

`reading_id: asset_manager_code_of_professional_conduct`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 1 questions, 1 essays across 1 cases
- essay% 100 · mcCalc% - · drlCalc% 0 · phoneQ 24 of 24 drills
- LOS command verbs: explain x2, determine x1, recommend x1

  Learning outcome statements (4):
  - explain the purpose of the Asset Manager Code and the benefits that may accrue to a firm that adopts the Code
  - explain the ethical and professional responsibilities required by the six General Principles of Conduct of the Asset Manager Code
  - determine whether an asset manager's practices and procedures are consistent with the Asset Manager Code
  - recommend practices and procedures designed to prevent violations of the Asset Manager Code

---

## Guidance for Standard V: Investment Analysis, Recommendations, and Actions

`reading_id: guidance_standard_v_investment_analysis`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 10 questions, 0 essays across 6 cases
- essay% 0 · mcCalc% 30 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Guidance for Standard III: Duties to Clients

`reading_id: guidance_standard_iii_duties_to_clients`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 13 questions, 1 essays across 8 cases
- essay% 8 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Guidance for Standard I: Professionalism

`reading_id: guidance_standard_i_professionalism`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 16 questions, 0 essays across 9 cases
- essay% 0 · mcCalc% 19 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Guidance for Standard VI: Conflicts of Interest

`reading_id: guidance_standard_vi_conflicts_of_interest`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 10 questions, 0 essays across 6 cases
- essay% 0 · mcCalc% 20 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Guidance for Standard IV: Duties to Employers

`reading_id: guidance_standard_iv_duties_to_employers`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 11 questions, 0 essays across 5 cases
- essay% 0 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Guidance for Standard II: Integrity of Capital Markets

`reading_id: guidance_standard_ii_integrity_capital_markets`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 6 questions, 0 essays across 4 cases
- essay% 0 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Code of Ethics and Standards of Professional Conduct

`reading_id: code_and_standards`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 0 questions, 0 essays across 0 cases
- essay% - · mcCalc% - · drlCalc% 1 · phoneQ 74 of 75 drills
- LOS command verbs: describe x1, explain x1

  Learning outcome statements (2):
  - describe the structure of the CFA Institute Professional Conduct Program and the disciplinary review process for the enforcement of the CFA Institute Code of Ethics and Standards of Professional Conduct
  - explain the ethical responsibilities required by the Code and Standards, including the subsections of each standard

---

## Guidance for Standard VII: Responsibilities as a CFA Institute Member or CFA Candidate

`reading_id: guidance_standard_vii_responsibilities`  —  Book 5 (Ethics), 12.5% of the exam

- bank: 3 questions, 0 essays across 2 cases
- essay% 0 · mcCalc% 0 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: demonstrate x1, recommend x1

  Learning outcome statements (2):
  - demonstrate a thorough knowledge of the CFA Institute Code of Ethics and Standards of Professional Conduct by interpreting the Code and Standards in various situations involving issues of professional integrity
  - recommend practices and procedures designed to prevent violations of the Code and Standards

---

## Yield Curve Strategies

`reading_id: yield_curve_strategies`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 7 questions, 5 essays across 4 cases
- essay% 71 · mcCalc% 100 · drlCalc% 5 · phoneQ 71 of 75 drills
- LOS command verbs: formulate x3, evaluate x2, describe x1, discuss x1

  Learning outcome statements (7):
  - describe the factors affecting fixed-income portfolio returns due to a change in benchmark yields
  - formulate a portfolio positioning strategy given forward interest rates and an interest rate view that coincides with the market view
  - formulate a portfolio positioning strategy given forward interest rates and an interest rate view that diverges from the market view in terms of rate level, slope, and shape
  - formulate a portfolio positioning strategy based upon expected changes in interest rate volatility
  - evaluate a portfolio's sensitivity using key rate durations of the portfolio and its benchmark
  - discuss yield curve strategies across currencies
  - evaluate the expected return and risks of a yield curve strategy

---

## Liability-Driven and Index-Based Strategies

`reading_id: liability_driven_and_index_based_strategies`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 25 questions, 12 essays across 4 cases
- essay% 48 · mcCalc% 100 · drlCalc% 7 · phoneQ 70 of 75 drills
- LOS command verbs: evaluate x2, compare x2, discuss x2, explain x1

  Learning outcome statements (7):
  - evaluate strategies for managing a single liability
  - compare strategies for a single liability and for multiple liabilities, including alternative means of implementation
  - evaluate liability-based strategies under various interest rate scenarios and select a strategy to achieve a portfolio's objectives
  - explain risks associated with managing a portfolio against a liability structure
  - discuss bond indexes and the challenges of managing a fixed-income portfolio to mimic the characteristics of a bond index
  - compare alternative methods for establishing bond market exposure passively
  - discuss criteria for selecting a benchmark and justify the selection of a benchmark

---

## Case Study in Portfolio Management: Institutional (Endowment)

`reading_id: case_study_in_portfolio_management_institutional_endowment`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 9 questions, 7 essays across 5 cases
- essay% 78 · mcCalc% 0 · drlCalc% 3 · phoneQ 73 of 75 drills
- LOS command verbs: discuss x3, analyze x2, demonstrate x2

  Learning outcome statements (7):
  - discuss tools for managing portfolio liquidity risk
  - discuss capture of the illiquidity premium as a long-term investment strategy
  - analyze asset allocation and portfolio construction in relation to liquidity needs and risk and return requirements and recommend actions to address identified needs
  - demonstrate the application of the Code of Ethics and Standards of Professional Conduct regarding the actions of individuals involved in manager selection
  - analyze the costs and benefits of derivatives versus cash market techniques for establishing or modifying asset class or risk exposures
  - demonstrate the use of derivatives overlays in tactical asset allocation and rebalancing
  - discuss ESG considerations in managing long-term institutional portfolios

---

## Active Equity Investing: Portfolio Construction

`reading_id: active_equity_investing_portfolio_construction`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 22 questions, 8 essays across 4 cases
- essay% 36 · mcCalc% 100 · drlCalc% 11 · phoneQ 67 of 75 drills
- LOS command verbs: discuss x5, describe x1, distinguish x1, evaluate x1

  Learning outcome statements (8):
  - describe elements of a manager's investment philosophy that influence the portfolio construction process
  - discuss approaches for constructing actively managed equity portfolios
  - distinguish between Active Share and active risk and discuss how each measure relates to a manager's investment strategy
  - discuss the application of risk budgeting concepts in portfolio construction
  - discuss risk measures that are incorporated in equity portfolio construction and describe how limits set on these measures affect portfolio construction
  - discuss how assets under management, position size, market liquidity, and portfolio turnover affect equity portfolio construction decisions
  - evaluate the efficiency of a portfolio structure given its investment mandate
  - discuss the long-only, long extension, long/short, and equitized market-neutral approaches to equity portfolio construction, including their risks, costs, and effects on potential alphas

---

## Fixed-Income Active Management: Credit Strategies

`reading_id: fixed_income_active_management_credit_strategies`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 31 questions, 12 essays across 4 cases
- essay% 39 · mcCalc% 68 · drlCalc% 1 · phoneQ 74 of 75 drills
- LOS command verbs: discuss x7, describe x4

  Learning outcome statements (11):
  - describe risk considerations for spread-based fixed-income portfolios
  - discuss the advantages and disadvantages of credit spread measures for spread-based fixed-income portfolios, and explain why option-adjusted spread is considered the most appropriate measure
  - discuss bottom-up approaches to credit strategies
  - discuss top-down approaches to credit strategies
  - discuss liquidity risk in credit markets and how liquidity risk can be managed in a credit portfolio
  - describe how to assess and manage tail risk in credit portfolios
  - discuss the use of credit default swap strategies in active fixed-income portfolio management
  - discuss various portfolio positioning strategies that managers can use to implement a specific credit spread view
  - discuss considerations in constructing and managing portfolios across international credit markets
  - describe the use of structured financial instruments as an alternative to corporate bonds in credit portfolios
  - describe key inputs, outputs, and considerations in using analytical tools to manage fixed-income portfolios

---

## Trade Strategy and Execution

`reading_id: trade_strategy_and_execution`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 17 questions, 10 essays across 3 cases
- essay% 59 · mcCalc% 57 · drlCalc% 3 · phoneQ 73 of 75 drills
- LOS command verbs: discuss x2, evaluate x2, compare x1, recommend x1, describe x1, contrast x1

  Learning outcome statements (9):
  - discuss motivations to trade and how they relate to trading strategy
  - discuss inputs to the selection of a trading strategy
  - compare benchmarks for trade execution
  - recommend and justify a trading strategy (given relevant facts)
  - describe factors that typically determine the selection of a trading algorithm class
  - contrast key characteristics of the following markets in relation to trade implementation: equity, fixed income, options and futures, OTC derivatives, and spot currency
  - explain how trade costs are measured and determine the cost of a trade
  - evaluate the execution of a trade
  - evaluate a firm's trading procedures, including processes, disclosures, and record keeping with respect to good governance

---

## Active Equity Investing: Strategies

`reading_id: active_equity_investing_strategies`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 31 questions, 12 essays across 4 cases
- essay% 39 · mcCalc% 100 · drlCalc% 5 · phoneQ 71 of 75 drills
- LOS command verbs: analyze x4, describe x3, compare x1, discuss x1

  Learning outcome statements (9):
  - compare fundamental and quantitative approaches to active management
  - analyze bottom-up active strategies, including their rationale and associated processes
  - analyze top-down active strategies, including their rationale and associated processes
  - analyze factor-based active strategies, including their rationale and associated processes
  - analyze activist strategies, including their rationale and associated processes
  - describe active strategies based on statistical arbitrage and market microstructure
  - describe how fundamental active investment strategies are created
  - describe how quantitative active investment strategies are created
  - discuss equity investment style classifications

---

## Index-Based Equity Strategies

`reading_id: index_based_equity_strategies`  —  Book 6 (PM Pathway), 32.5% of the exam

- bank: 20 questions, 8 essays across 3 cases
- essay% 40 · mcCalc% 100 · drlCalc% 0 · phoneQ 75 of 75 drills
- LOS command verbs: compare x4, discuss x1, explain x1

  Learning outcome statements (6):
  - compare factor-based strategies to market-capitalization-weighted indexing
  - compare different approaches to index-based equity strategies
  - compare different approaches to index-based equity investing
  - compare the full replication, stratified sampling, and optimization approaches for the construction of index-based equity portfolios
  - discuss potential causes of tracking error and methods to control tracking error for index-based equity portfolios
  - explain sources of return and risk to an index-based equity portfolio
