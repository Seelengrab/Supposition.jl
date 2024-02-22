using PrecompileTools

@setup_workload begin

    works(i::Int8) = i isa Int8
    breaks(i::Int8) = i isa Int
    errors(_) = error()

    @compile_workload begin
        intgen = Data.Integers{Int8}()
        redirect_stdout(devnull) do
            @check record=false verb=false works(intgen)
            @check record=false broken=true breaks(intgen)
            @check record=false broken=true errors(intgen)
        end
        for T in (Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64)
            ig = Data.Integers{T}()
            example(Data.Vectors(ig))
            example(ig)
        end
        for T in (Float16, Float32, Float64)
            ig = Data.Floats{T}()
            example(Data.Vectors(ig))
            example(ig)
        end
        example(Data.Text(Data.AsciiCharacters()))
        example(Data.Text(Data.Characters()))
    end
end
