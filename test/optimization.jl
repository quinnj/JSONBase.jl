module test_optimization

using JSONBase, JET

struct OptimizationFailureChecker end
function JET.configured_reports(::OptimizationFailureChecker, reports::Vector{JET.InferenceErrorReport})
    return filter(reports) do @nospecialize report::JET.InferenceErrorReport
        isa(report, JET.OptimizationFailureReport)
    end
end

# https://github.com/quinnj/JSONBase.jl/issues/2
struct Simple
    a::Int
    b::Int
end
@test_opt annotate_types=true report_config=OptimizationFailureChecker() JSONBase.materialize("""{ "a": 1, "b": 2 }""", Simple)

struct Inner
    b::Int
end
struct Outer
    a::Int
    b::Inner
end
@test_opt annotate_types=true report_config=OptimizationFailureChecker() JSONBase.materialize("""{ "a": 1, "b": { "b": 2 } }""", Outer)

struct SelfRecur
    a1::Int
    a2::Union{Nothing,SelfRecur}
end
@test_opt annotate_types=true report_config=OptimizationFailureChecker() JSONBase.materialize("""{ "a1": 1, "a2": { "a1": 2 } }""", SelfRecur)

struct RecurInner{T}
    a::T
end
struct RecurOuter
    a1::Int
    a2::Union{Nothing,RecurInner{RecurOuter}}
end
@test_opt annotate_types=true report_config=OptimizationFailureChecker() JSONBase.materialize("""{ "a1": 1, "a2": { "a": { "a1": 2 } } }""", RecurOuter)

end # module test_optimization
