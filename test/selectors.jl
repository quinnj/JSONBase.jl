using JSONBase, JSONBase.Selectors, Test

struct Arr
    arr
end

function Selectors.foreach(f, items::Arr)
    for (i, x) in enumerate(getfield(items, :arr))
        ret = f(i, x)
        ret !== Selectors.NoValue() && return ret
    end
    return Selectors.NoValue()
end

Selectors.SelectorType(::Arr) = Selectors.ArrayLike()
Selectors.@selectors Arr

struct NT
    nt
end

function Selectors.foreach(f, nt::NT)
    for (k, v) in pairs(getfield(nt, :nt))
        ret = f(k, v)
        ret !== Selectors.NoValue() && return ret
    end
    return Selectors.NoValue()
end

Selectors.SelectorType(::NT) = Selectors.ObjectLike()
Selectors.@selectors NT

x = NT((
    store = NT((
        book = Arr([
            NT((
                category = "reference",
                author = "Nigel Rees",
                title = "Sayings of the Century",
                price = 8.95
            )),
            NT((
                category = "fiction",
                author = "Herman Melville",
                title = "Moby Dick",
                isbn = "0-553-21311-3",
                price = 8.99
            )),
            NT((
                category = "fiction",
                author = "J.R.R. Tolkien",
                title = "The Lord of the Rings",
                isbn = "0-395-19395-8",
                price = 22.99
            ))
        ]),
        bicycle = NT((
            color = "red",
            price = 19.95
        ))
    )),
    expensive = 10
))

@testset "Selector methods" begin
    # direct indexing methods
    @test x.expensive == 10
    @test x["store"][:bicycle].price == 19.95
    @test x[:] isa JSONBase.List
    @test x[[:store, :expensive]] isa JSONBase.List
    @test x[:] == x[[:store, :expensive]] == x[x -> [:store, :expensive]]
    @test x.store == x[:, (k, v) -> k == :store][1]
    # on array
    books = x.store.book
    @test books[1].author == "Nigel Rees"
    @test books[1:2][1].author == "Nigel Rees"
    @test books[[1, 2]][1].author == "Nigel Rees"
    @test books[:] isa JSONBase.List
    @test books[:, (i, x) -> x.category == "reference"][1].author == "Nigel Rees"

    # broadcast methods
    # on array
    @test books.title == ["Sayings of the Century", "Moby Dick", "The Lord of the Rings"]
    @test books["title"] == ["Sayings of the Century", "Moby Dick", "The Lord of the Rings"]
    @test books[:title][1] == "Sayings of the Century"

    # recursive methods
    @test x[~, :expensive] == [10]
    @test x[~, "store"] == [x.store]
    @test x[~, :] isa JSONBase.List

    # translate jsonpath
    # $.store.book[*].author; The authors of all books
    x.store.book.author 
    # $..author; All authors
    x[~, :author]
    # $.store.*; All things, both books and bicycles
    x.store[:]
    # $.store..price; The price of everything
    x.store[~, :price]
    # $..book[2]; The second book
    x[~, :book][2]
    # $..book[(@.length-1)]; The last book in order
    x[~, :book][end]
    # $..book[?(@.isbn)]; All books with an ISBN number
    # x[~, :book][:, x -> haskey(x, :isbn)]
    # $.store.book[?(@.price < 10)]; All books in the store cheaper than 10
    x.store.book[:, (i, x) -> x.price < 10]
    # $..book[?(@.price <= $['expensive'])]; All books in the store that are not too expensive
    x[~, :book][:, (i, y) -> y.price <= x.expensive]
    # $..book[?(@.author =~ /.*REES/i)]
    x[~, :book][:, (i, y) -> occursin(r"REES"i, y.author)]
    # $..*; All members of JSON structure
    x[~, :]
end
