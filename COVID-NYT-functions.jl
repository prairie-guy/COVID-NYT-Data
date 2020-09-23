using CSV, DataFrames, Plots, Dates

# May be required if there are problems with @tbl
# using WebIO, IJulia; WebIO.install_jupyter_nbextension()
# If needed, may need to reinstall jupyter

# TableView is a better way to display DataFrames
# @tbl macro makes it easy to use
using Tables, TableView
macro tbl(df)
    :(showtable($df))
end

function get_state_populations()
    url = "https://raw.githubusercontent.com/prairie-guy/2019-State-and-County-Population-with-FIPS-key/master/2019_state_populations.csv"
    CSV.read(download(url),type=String,types=Dict(3=>Int64))
end

function get_county_populations()
    url = "https://raw.githubusercontent.com/prairie-guy/2019-State-and-County-Population-with-FIPS-key/master/2019_county_populations.csv"
    # Field '4' is fips, which should be a string
    CSV.read(download(url),type=String,types=Dict(4=>Int64))
end

function moving_avg(b, days::Int)
    total = copy(b)
    days <= length(b) || (total .= 0.0; return(total))
    for i in 1:days-1
        new = b[1:i]
        append!(new,b[1:end-i])
        total = total .+ new
    end
    #println(b)
    #println(total)
    round.(total./days,digits=1)
end

function total(b)
    a = copy(b)
    #println(a)
    last = 0
    for (i,v) in enumerate(a)
        a[i] = v + last
        last = a[i]
    end
    a
end

function percent_change(b, days::Int) # a,b are vectors
    a = copy(b)
    days <= length(b)  || (a .= 0.0;return(a))
    a = a[1:end-days]
    a = append!(zeros(Float64,days),a)
    #println(b)
    #println(a)
    round.(100*(b./a .- 1),digits=1)
end

delta(b, days::Int=1) = append!([0],b[2:end] - b[1:end-1])

function delta_2(b, days::Int=1) # a,b are vectors
    a = copy(b)
    days <= length(b)  || (a .= 0;return(a))
    a = a[1:end-days]
    a = append!(zeros(Int64,days),a)
    #println(b)
    #println(a)
    #round.(b .- a,digits=1)
    b .- a
end


function get_nyt_county_covid_data(days_ma::Int=7,days_delta::Int=7) # Assumes {:cases, :deaths} exist
    url = "https://raw.githubusercontent.com/nytimes/covid-19-data/master/us-counties.csv"
    # Field '4' is fips, which should be a string
    dfc = CSV.read(download(url),silencewarnings=true,types=Dict(4=>String))

    # 'true' means to select 'states/counties'
    dfc = make_df_region(dfc, true, days_ma, days_delta) 

    dfc     = filter(r->r.county != "Unknown",dfc)
    pops    = get_county_populations()
    df_fips = DataFrame(fips=pops.fips,population=pops.population)

    # New York City is considered a county
    nyc = filter(r->  r.state == "New York",
                 filter(r->
            r.county =="Bronx County" ||
            r.county =="Kings County" ||
            r.county =="New York County" ||
            r.county =="Queens County" ||
            r.county =="Richmond County",
        pops))
    nyc_pop = combine(nyc,:population=>sum)[1,1]

    # Kansas City is considered a county
    kc = filter(r->  r.state == "Missouri",
            filter(r->
            r.county =="Cass County" ||
            r.county =="Clay County" ||
            r.county =="Jackson County" ||
            r.county =="Platte County",
        pops))
    kc_pop = combine(kc,:population=>sum)[1,1]

    # Joplin City, MO is reported separately from Jasper and Newton counties
    # Population: https://www.census.gov/quickfacts/fact/table/joplincitymissouri/PST045219
    jc_pop = 50000


    # County Populations are not available for:
    # "Virgin Islands","Puerto Rico", "Northern Mariana Islands"
    # Filter these out
    excluded_st = ["Virgin Islands","Puerto Rico", "Northern Mariana Islands"]
    dfc = filter(r-> r.state ∉ excluded_st,dfc)

    # Join 'population with into dfc'
    dfc = leftjoin(dfc,df_fips, on="fips")
    dfc[dfc[:,:county] .== "New York City",:population] .= nyc_pop
    dfc[dfc[:,:county] .== "Kansas City"  ,:population] .= kc_pop
    dfc[dfc[:,:county] .== "Joplin"  ,:population] .= jc_pop
    dfc[ismissing.(dfc[:,:fips]),:fips] .= "-1"
    
    dfc
end

function get_nyt_state_covid_data(days_ma::Int=7,days_delta::Int=7) # Assumes {:cases, :deaths} exist
    url = "https://raw.githubusercontent.com/nytimes/covid-19-data/master/us-states.csv"

    # Field '3' is fips, which should be a string
    dfc = CSV.read(download(url),silencewarnings=true,types=Dict(3=>String))

    # 'false' means to select 'states'
    dfc = make_df_region(dfc, false, days_ma, days_delta) 

    # In 'pops' state are represented as 'xx000' but 'xx' in dfc
    pops      = get_state_populations()
    pops.fips = map(r->r[1:2],pops.fips)
    df_fips   = DataFrame(fips=pops.fips,population=pops.population)

    # Join 'population with into dfc'
    # Puerto Rico, Virgin Islands and Guam are not in NYT data and are removed
    dfc = leftjoin(dfc,df_fips, on="fips")
    dfc = filter(r->!ismissing(r.population),dfc)
    
    dfc
end

# Internal function only
function make_df_region(df_region, region, days_ma, days_delta) 
    # true => 'state/county', false => 'state'
    by_region = region ? [:state,:county] : [:state]

    dfc = sort(df_region)
    dfc[!,:casesMA]                  .= 0.0
    dfc[!,:casesIncrease]            .= 0
    dfc[!,:casesIncreaseMA]          .= 0.0
    dfc[!,:pch_casesMA]              .= 0.0
    dfc[!,:pch_casesIncreaseMA]      .= 0.0
    
    dfc[!,:deathsMA]                 .= 0.0
    dfc[!,:deathsIncrease]           .= 0
    dfc[!,:deathsIncreaseMA]         .= 0.0
    dfc[!,:pch_deathsMA]             .= 0.0
    dfc[!,:pch_deathsIncreaseMA]     .= 0.0
    
    for df in groupby(dfc, by_region)
        df.casesMA                   .= moving_avg(df.cases,days_ma)        
        df.casesIncrease             .= delta(df.cases)
        df.casesIncreaseMA           .= moving_avg(df.casesIncrease,days_ma)
        df.pch_casesMA               .= percent_change(df.casesMA,days_delta)
        df.pch_casesIncreaseMA       .= percent_change(df.casesIncreaseMA,days_delta)
        
        df.deathsMA                  .= moving_avg(df.deaths,days_ma)
        df.deathsIncrease            .= delta(df.deaths)
        df.deathsIncreaseMA          .= moving_avg(df.deathsIncrease,days_ma)
        df.pch_deathsMA              .= percent_change(df.deathsMA,days_delta)
        df.pch_deathsIncreaseMA      .= percent_change(df.deathsIncreaseMA,days_delta)
    end
    dfc
end


function select_region(dfc::DataFrame, state::String, county::String, cols=[])
    df = filter(r-> r.state .== state && r.county .== county, dfc)
    isempty(cols) ? df : df[:,cols]
end

function select_region(dfc::DataFrame, state::String, cols=[])
    df = filter(r-> r.state .== state, dfc)
    isempty(cols) ? df : df[:,cols]
end


function aggregate_by_county(dfc, 
                             cols=[:date,:state, :county,:fips,
                                   :cases,:casesMA,:pch_casesMA,
                                   :casesIncrease,:casesIncreaseMA,:pch_casesIncreaseMA,
                                   :deaths,:deathsMA,:pch_deathsMA,
                                   :deathsIncrease,:deathsIncreaseMA,:pch_deathsIncreaseMA,
                                   :population];
                             names = [], select_by = last)
    aggregate_by_region(dfc, cols, names, true, select_by)
end

function aggregate_by_state(dfc,
                            cols=[:date,:state,:fips,
                                  :cases,:casesMA,:pch_casesMA,
                                   :casesIncrease,:casesIncreaseMA,:pch_casesIncreaseMA,
                                   :deaths,:deathsMA,:pch_deathsMA,
                                  :deathsIncrease,:deathsIncreaseMA,:pch_deathsIncreaseMA,
                                  :population];
                            names = [], select_by = last)
    aggregate_by_region(dfc, cols,  names, false, select_by)
end


# Internal function
function aggregate_by_region(dfc, cols, names, region, select_by)
    by_region = region ? [:state,:county] : [:state]
    df = DataFrame()
    for g in groupby(dfc,by_region)
        row = select_by(g)
        push!(df,row)
    end
    df = df[:,cols]
    if !isempty(names) 
        rename!(df,names)
    end
    sort(df)
end   

function graph_epidemiological_curve(dfc::DataFrame, state::String, county::String)
    df = select_region(dfc,state,county)
    bar(df.date, df.casesIncrease, label = "Daily Cases")
    plot!(df.date, df.casesIncreaseMA,
          xticks=Date.(df.date)[reverse(end:-14:1)], xrotation=45,
          lw=2, color=:red,leg=:topleft, label = "7-day Avg")
    xlabel!("Date")
    ylabel!("New Cases")
    title!("New Daily Cases\n$(county), $(state)")   
end

function graph_epidemiological_curve(dfc::DataFrame, state::String)
    df = select_region(dfc,state)
    bar(df.date, df.casesIncrease, label = "Daily Cases")
    plot!(df.date, df.casesIncreaseMA,
          xticks=Date.(df.date)[reverse(end:-14:1)], xrotation=45,
          lw=2, color=:red,leg=:topleft, label = "7-day Avg")
    xlabel!("Date")
    ylabel!("New Cases")
    title!("New Daily Cases\n$(state)")   
end
