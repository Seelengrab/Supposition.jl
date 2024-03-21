using PrecompileTools

@setup_workload begin
    works(i::Int8) = i isa Int8
    breaks(i::Int8) = i isa Int
    targets(i::Int8) = begin
        target!(i)
        i isa Int
    end
    events(i::Int8) = begin
        event!(i)
        i isa Int
    end
    assumes(i::Int8) = begin
        assume!(true)
        i isa Int
    end
    rejects(i::Int8) = begin
        reject!()
        i isa Int
    end
    errors(_) = error()
    double(x) = 2x

    @compile_workload begin
        intgen = Data.Integers{Int8}()
        c = Supposition.merge(Supposition.DEFAULT_CONFIG[]; db=false, record=false, max_examples=10)
        redirect_stdout(devnull) do
            @with Supposition.DEFAULT_CONFIG => c begin
                @check verbose=false works(intgen)
                @check broken=true breaks(intgen)
                @check broken=true targets(intgen)
                @check broken=true events(intgen)
                @check broken=true assumes(intgen)
                @check rejects(intgen)
                @check broken=true errors(intgen)
            end
        end
        for T in (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64)
            ig = Data.Integers{T}()
            example(Data.Vectors(ig))
            example(ig)
            example(filter(iseven, ig))
            example(map(double, ig))
        end
        for T in (Float16, Float32, Float64)
            ig = Data.Floats{T}()
            example(Data.Vectors(ig))
            example(ig)
            example(filter(iseven, ig))
            example(map(double, ig))
        end
        example(Data.Text(Data.AsciiCharacters()))
        example(Data.Text(Data.Characters()))
    end
end
