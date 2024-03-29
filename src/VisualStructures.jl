module VisualStructures

using FinEtools
using PlotlyJS
using JSON
using LinearAlgebra: norm, I
using Statistics

const BACKGROUNDCOLOR = "rgb(230, 230,230)"

function removepair(nt, key)
    return (; delete!(Dict(pairs(nt)), key)...)
end

function addpair(nt, key, val)
    d = Dict()
    for p in pairs(nt)
        d[p[1]] = p[2]
    end
    d[key] = val
    return (; d...)
end

function _beam_local_frame!(F0, x0, x1x2_vector)
    # This is the element frame in the configuration t=0
    F0[:,1] = (x0[2,:]-x0[1,:]);
    L0 = norm(@view F0[:,1]);
    F0[:,1] /= L0;
    #     F0(:,3)=skewmat(F0(:,1))*x1x2_vector;
    F0[:,3] .= (-F0[3,1]*x1x2_vector[2]+F0[2,1]*x1x2_vector[3],
                 F0[3,1]*x1x2_vector[1]-F0[1,1]*x1x2_vector[3],
                -F0[2,1]*x1x2_vector[1]+F0[1,1]*x1x2_vector[2]);
    F0[:,3] /= norm(@view F0[:,3]);
    #     F0(:,2)=skewmat(F0(:,3))*F0(:,1);
    F0[:,2] .= (-F0[3,3]*F0[2,1]+F0[2,3]*F0[3,1],
                 F0[3,3]*F0[1,1]-F0[1,3]*F0[3,1],
                -F0[2,3]*F0[1,1]+F0[1,3]*F0[2,1]);
    return L0, F0
end

"""
    space_aspectratio(xyz; margin = 0.0)

Compute the aspect ratio of the space given by the array of locations
"""
function space_aspectratio(xyz; margin = 0.0)
    xr = maximum(xyz[:, 1]) - minimum(xyz[:, 1])
    yr = maximum(xyz[:, 2]) - minimum(xyz[:, 2])
    zr = maximum(xyz[:, 3]) - minimum(xyz[:, 3])
    if margin == 0.0
        margin = (xr + yr + zr) / 10000
    end
    xr += margin
    yr += margin
    zr += margin
    return [1.0, yr / xr, zr / xr]
end

"""
    plot_space_box(xyz; color = BACKGROUNDCOLOR)

Plot points to set up the global 3D box
"""
function plot_space_box(xyz; color = BACKGROUNDCOLOR)
    return [scatter3d(;x=xyz[:, 1],y=xyz[:, 2], z=xyz[:, 3], mode="markers",
        marker=attr(color=color, size=1, symbol="circle",
            line=attr(color=color, width=1)),
        line=attr(color=color, width=1))]
end

"""
    plot_points(xyz; color = "#1f77b4", msize = 4)

Plot points as markers
"""
function plot_points(xyz; color = "#1f77b4", msize = 4)
    return [scatter3d(;x=xyz[:, 1],y=xyz[:, 2], z=xyz[:, 3], mode="markers",
        marker=attr(color=color, size=msize, symbol="circle",
            line=attr(color=color, width=3)),
        line=attr(color="#1f77b4", width=4))]
end

"""
    plot_nodes(fens; color = "#1f77b4")

Plot nodes as markers
"""
function plot_nodes(fens; color = "#1f77b4")
    return plot_points(fens.xyz; color = color)
end

"""
    plot_midline(fens, fes; color = "rgb(155, 155, 255)", lwidth = 4)

Plot the midline
"""
function plot_midline(fens, fes; kwargs...)
    x = deepcopy(fens.xyz)
    if :x in keys(kwargs)
        x = kwargs[:x]; kwargs = removepair(kwargs, :x)
    end
    u = fill(0.0, size(x))
    if :u in keys(kwargs)
        u = kwargs[:u]; kwargs = removepair(kwargs, :u)
    end
    lwidth = 4
    if :lwidth in keys(kwargs)
        lwidth = kwargs[:lwidth]; kwargs = removepair(kwargs, :lwidth)
    end
    color = "rgb(155, 155, 255)"
    if :color in keys(kwargs)
        color = kwargs[:color]; kwargs = removepair(kwargs, :color)
    end
    xyz = fill(0.0, 2, 3)
    t = PlotlyBase.GenericTrace[]
    for c in fes.conn
        xyz[1, :] .= x[c[1], :] .+ u[c[1], :]
        xyz[2, :] .= x[c[2], :] .+ u[c[2], :]
        push!(t, scatter3d(;x=xyz[:, 1], y=xyz[:, 2], z=xyz[:, 3], mode="lines", line=attr(color=color, width=lwidth)))
    end
    return t
end

function _circular(dimensions, buffers, x1x2_vector, R1I, R1J; kwargs...)
    radius = dimensions[1]
    F0, x0, xt, eecc, c, s, xc, faces, facecolors = buffers
    L0, F0 = _beam_local_frame!(F0, x0, x1x2_vector)
    FtI=R1I*F0;
    FtJ=R1J*F0;
    nseg = length(c)-1
    for j in 1:nseg+1
        xc[j,:]          = xt[1,:] + eecc[1]*FtI[:,1] + eecc[3]*FtI[:,2] + eecc[4]*FtI[:,3] + radius*c[j]*FtI[:,2] + radius*s[j]*FtI[:,3];
        xc[j+(nseg+1),:] = xt[2,:] + eecc[2]*FtJ[:,1] + eecc[3]*FtJ[:,2] + eecc[4]*FtJ[:,3] + radius*c[j]*FtI[:,2] + radius*s[j]*FtI[:,3];
    end
    return mesh3d(;x=xc[:, 1],y=xc[:, 2], z=xc[:, 3], i=faces[:, 1].-1, j=faces[:, 2].-1, k=faces[:, 3].-1, facecolor=facecolors, kwargs...)
end

function _rectangular(dimensions, buffers, x1x2_vector, R1I, R1J; kwargs...)
    b, h = dimensions[1:2]./2 # departures from the midline by half the dimension
    F0, x0, xt, eecc, c, s, xc, faces, facecolors = buffers
    L0, F0 = _beam_local_frame!(F0, x0, x1x2_vector)
    FtI=R1I*F0;
    FtJ=R1J*F0;
    for j in 1:4+1
        xc[j,:]       = xt[1,:] + eecc[1]*FtI[:,1] + eecc[3]*FtI[:,2] + eecc[4]*FtI[:,3] + c[j]*b*FtI[:,2] + s[j]*h*FtI[:,3];
        xc[j+(4+1),:] = xt[2,:] + eecc[2]*FtJ[:,1] + eecc[3]*FtJ[:,2] + eecc[4]*FtJ[:,3] + c[j]*b*FtJ[:,2] + s[j]*h*FtJ[:,3];
    end
    return mesh3d(;x=xc[:, 1],y=xc[:, 2], z=xc[:, 3], i=faces[:, 1].-1, j=faces[:, 2].-1, k=faces[:, 3].-1, facecolor=facecolors, kwargs...)
end

"""
    plot_solid(fens, fes; kwargs...)

Plot beam structure as solid
"""
function plot_solid(fens, fes; kwargs...)
    dfes = delegateof(fes)
    x = deepcopy(fens.xyz)
    if :x in keys(kwargs)
        x = kwargs[:x]; kwargs = removepair(kwargs, :x)
    end
    u = fill(0.0, size(x))
    if :u in keys(kwargs)
        u = kwargs[:u]; kwargs = removepair(kwargs, :u)
    end
    R = fill(0.0, size(x, 1), 9)
    for j in 1:size(R, 1)
        R[j, :] .= Matrix(1.0 * I, 3, 3)[:]
    end
    if :R in keys(kwargs)
        R = kwargs[:R]; kwargs = removepair(kwargs, :R)
    end
    ecc = fill(0.0, count(fes), 4)
    if :ecc in keys(kwargs)
        ecc = kwargs[:ecc]; kwargs = removepair(kwargs, :ecc)
    end
    facecolor = "rgb(255, 155, 55)"
    if :facecolor in keys(kwargs)
        facecolor = kwargs[:facecolor]; kwargs = removepair(kwargs, :facecolor)
    end
    if !(:flatshading in keys(kwargs))
        kwargs = addpair(kwargs, :flatshading, true); 
    end
    F0 = fill(0.0, 3, 3)
    x0 = fill(0.0, 2, 3)
    xt = fill(0.0, size(x0))
    R1I = Matrix(1.0 * I, 3, 3)
    R1J = Matrix(1.0 * I, 3, 3)
    eecc = fill(0.0, 4)
    if dfes.crosssection.shape == "circle"
        nseg = 13
        v = vec((collect(1:nseg+1).-1)./nseg)
        c = cos.(2*pi*v);
        s = sin.(2*pi*v);
        faces = fill(0, 2*nseg, 3)
        for i in 1:nseg
            faces[i, :] .= (i+1, i, i+nseg+1)
            faces[i+nseg, :] .= (i+nseg+1, i+nseg+2, i+1)
        end
        xc = zeros(2*(nseg+1),3);
        facecolors = fill(facecolor, 2*nseg)
        buffers = (F0, x0, xt, eecc, c, s, xc, faces, facecolors)
        _draw = _circular
    elseif dfes.crosssection.shape == "rectangle"
        faces = fill(0, 2*4, 3)
        for i in 1:4
            faces[i, :] .= (i+1, i, i+4+1)
            faces[i+4, :] .= (i+4+1, i+4+2, i+1)
        end
        c = [1, -1, -1, 1, 1]
        s = [1, 1, -1, -1, 1]
        xc = zeros(2*(4+1),3);
        facecolors = fill(facecolor, 2*4)
        buffers = (F0, x0, xt, eecc, c, s, xc, faces, facecolors)
        _draw = _rectangular
    end

    t = PlotlyBase.GenericTrace[]
    for i in 1:count(fes)
        c = fes.conn[i]
        x0[1, :] .= x[c[1], :]
        x0[2, :] .= x[c[2], :]
        xt[1, :] .= x[c[1], :] .+ u[c[1], :]
        xt[2, :] .= x[c[2], :] .+ u[c[2], :]
        R1I[:] .= R[c[1], :]
        R1J[:] .= R[c[2], :]
        eecc .= ecc[i, :]
        push!(t, _draw(dfes.dimensions[i], buffers, dfes.x1x2_vector[i], R1I, R1J; kwargs...))
    end
    return t
end

"""
    render(traces; kwargs...)

Render a plot

Key word arguments:
- `config = PlotConfig()`
"""
function render(traces; kwargs...)
    layout = default_layout_3d(; kwargs...)
    if :layout in keys(kwargs)
        layout = kwargs[:layout]; kwargs = removepair(kwargs, :layout)
    end
    # Default options: show the "save to chart studio" button
    config = PlotConfig(
        showLink=true, 
        plotlyServerURL="https://chart-studio.plotly.com"
        )
    # Should we override config because they were supplied as argument?
    if :config in keys(kwargs)
        config = kwargs[:config]; kwargs = removepair(kwargs, :config)
    end
    p = plot(traces, layout; config = config)
    display(p)
    return p
end

"""
    default_layout_3d(; kwargs...)

Set up the default layout for three-dimensional plots
"""
function default_layout_3d(; kwargs...)
    aspectratio = "data" # plotly.js tries to be smart by scaling back the scene to a cube when x/y/z are too dissimilar.
    # By setting scene.aspectratio: 'data', the x/y/z range are always honored.
    if :aspectratio in keys(kwargs)
        aspectratio = kwargs[:aspectratio]; kwargs = removepair(kwargs, :aspectratio)
    end
    title = ""
    if :title in keys(kwargs)
        title = kwargs[:title]; kwargs = removepair(kwargs, :title)
    end
    autosize = true
    if :autosize in keys(kwargs)
        autosize = kwargs[:autosize]; kwargs = removepair(kwargs, :autosize)
    end
    width = 360
    if :width in keys(kwargs)
        width = kwargs[:width]; kwargs = removepair(kwargs, :width)
    end
    height = 240
    if :height in keys(kwargs)
        height = kwargs[:height]; kwargs = removepair(kwargs, :height)
    end
    scene=attr(
        xaxis = attr(title="X", gridcolor="rgb(255, 255, 255)",
          zerolinecolor="rgb(255, 255, 255)",
          showbackground=true,
          backgroundcolor=BACKGROUNDCOLOR),
        yaxis = attr(title="Y", gridcolor="rgb(255, 255, 255)",
           zerolinecolor="rgb(255, 255, 255)",
           showbackground=true,
           backgroundcolor=BACKGROUNDCOLOR),
        zaxis = attr(title="Z", gridcolor="rgb(255, 255, 255)",
           zerolinecolor="rgb(255, 255, 255)",
           showbackground=true,
           backgroundcolor=BACKGROUNDCOLOR),
        camera = attr(
            up=attr(x=0, y=0, z=1),
            center=attr(x=0, y=0, z=0),
            eye=attr(x=1.25, y=1.25, z=1.25),
            projection = attr(type = "orthographic") # alternative: projection = attr(type = "perspective")
            ),
        aspectratio = aspectratio,
        aspectmode = "manual")
    if autosize
        layout = Layout(autosize=autosize, title=title, scene=scene, showlegend=false)
    else
        layout = Layout(width=width, height=height, title=title, scene=scene, showlegend=false,)
    end
    
    return layout
end

"""
    save_to_json(pl, fn)

Save plot to a JSON file
"""
function save_to_json(pl, fn)
    savejson(pl, fn)
end

"""
    plot_from_json(fn)

Retrieve plot from a JSON file and display it
"""
function plot_from_json(fn)
    pl = open(fn, "r") do f; 
        plot(JSON.parse(Plot, String(read(f)))) 
    end
    return pl
end


"""
    plot_midline(fens, fes; color = "rgb(155, 155, 255)", lwidth = 4)

Plot the midsurface

- `x`: array of node locations
- `u`: array of node displacements
- `R`: array of node rotation matrices
- `facecolor`: color of the surface
- `lwidth`: house thick should the lines be?
"""
function plot_midsurface(fens, fes; kwargs...) 
    x = deepcopy(fens.xyz)
    if :x in keys(kwargs)
        x = kwargs[:x]; kwargs = removepair(kwargs, :x)
    end
    u = fill(0.0, size(x))
    if :u in keys(kwargs)
        u = kwargs[:u]; kwargs = removepair(kwargs, :u)
    end
    lwidth = 4
    if :lwidth in keys(kwargs)
        lwidth = kwargs[:lwidth]; kwargs = removepair(kwargs, :lwidth)
    end
    facecolor = "rgb(155, 155, 255)"
    if :facecolor in keys(kwargs)
        facecolor = kwargs[:facecolor]; kwargs = removepair(kwargs, :facecolor)
    end
    facecolors = fill(facecolor, count(fes))
    faces = connasarray(fes).-1
    t = PlotlyBase.GenericTrace[]
    push!(t, mesh3d(;x=x[:, 1]+u[:, 1], y=x[:, 2]+u[:, 2], z=x[:, 3]+u[:, 3], i=faces[:, 1], j=faces[:, 2], k=faces[:, 3], facecolor=facecolors, kwargs...))
    if nodesperelem(fes)   == 4
        push!(t, mesh3d(;x=x[:, 1]+u[:, 1], y=x[:, 2]+u[:, 2], z=x[:, 3]+u[:, 3], i=faces[:, 4], j=faces[:, 1], k=faces[:, 3], facecolor=facecolors, kwargs...))
    end
    return t
end

"""
    plot_triads(fens; kwargs...)

Plot the node triads.

- `x`: array of node locations
- `u`: array of node displacements
- `R`: array of node rotation matrices
- `triad_length`: how long should a triad arrow be?
- `lwidth`: house thick should the lines be?
"""
function plot_triads(fens; kwargs...)
    x = deepcopy(fens.xyz)
    if :x in keys(kwargs)
        x = kwargs[:x]; kwargs = removepair(kwargs, :x)
    end
    u = fill(0.0, size(x))
    if :u in keys(kwargs)
        u = kwargs[:u]; kwargs = removepair(kwargs, :u)
    end
    R = fill(0.0, size(x, 1), 9)
    for j in 1:size(R, 1)
        R[j, :] .= Matrix(1.0 * I, 3, 3)[:]
    end
    if :R in keys(kwargs)
        R = kwargs[:R]; kwargs = removepair(kwargs, :R)
    end
    triad_length = 1.0
    if :triad_length in keys(kwargs)
        triad_length = kwargs[:triad_length]; kwargs = removepair(kwargs, :triad_length)
    end
    lwidth = 4
    if :lwidth in keys(kwargs)
        lwidth = kwargs[:lwidth]; kwargs = removepair(kwargs, :lwidth)
    end

    R1I = Matrix(1.0 * I, 3, 3)

    colors = ["rgb(255, 15, 25)", "rgb(15, 255, 25)", "rgb(25, 15, 255)"]
    
    t = PlotlyBase.GenericTrace[]
    for i in 1:count(fens)
        R1I[:] .= R[i, :]
        for tv in 1:3
            X = fill(0.0, 2) # must allocate here, the scatter3d stores reference to it
            Y = fill(0.0, 2)
            Z = fill(0.0, 2)
            X[1] = x[i, 1] .+ u[i, 1]
            Y[1] = x[i, 2] .+ u[i, 2]
            Z[1] = x[i, 3] .+ u[i, 3]
            X[2] = X[1] .+ triad_length*R1I[1, tv]
            Y[2] = Y[1] .+ triad_length*R1I[2, tv]
            Z[2] = Z[1] .+ triad_length*R1I[3, tv]
            push!(t, scatter3d(;x=X, y=Y, z=Z, mode="lines", line=attr(color=colors[tv], width=lwidth), kwargs...))
        end
    end
    return t
end

"""
    plot_local_frames(fens, fes; kwargs...)

Plot the element local frames.

- `x`: array of node locations
- `u`: array of node displacements
- `R`: array of node rotation matrices
- `triad_length`: how long should a triad arrow be?
- `lwidth`: house thick should the lines be?
"""
function plot_local_frames(fens, fes; kwargs...)
    dfes = delegateof(fes)
    x = deepcopy(fens.xyz)
    if :x in keys(kwargs)
        x = kwargs[:x]; kwargs = removepair(kwargs, :x)
    end
    u = fill(0.0, size(x))
    if :u in keys(kwargs)
        u = kwargs[:u]; kwargs = removepair(kwargs, :u)
    end
    R = fill(0.0, size(x, 1), 9)
    for j in 1:size(R, 1)
        R[j, :] .= Matrix(1.0 * I, 3, 3)[:]
    end
    if :R in keys(kwargs)
        R = kwargs[:R]; kwargs = removepair(kwargs, :R)
    end
    triad_length = 1.0
    if :triad_length in keys(kwargs)
        triad_length = kwargs[:triad_length]; kwargs = removepair(kwargs, :triad_length)
    end
    lwidth = 4
    if :lwidth in keys(kwargs)
        lwidth = kwargs[:lwidth]; kwargs = removepair(kwargs, :lwidth)
    end

    colors = ["rgb(255, 15, 25)", "rgb(15, 255, 25)", "rgb(25, 15, 255)"]

    F0 = fill(0.0, 3, 3)
    x0 = fill(0.0, 2, 3)
    xt = fill(0.0, size(x0))
    R1I = Matrix(1.0 * I, 3, 3)
    R1J = Matrix(1.0 * I, 3, 3)


    t = PlotlyBase.GenericTrace[]
    for i in 1:count(fes)
        c = fes.conn[i]
        x0[1, :] .= x[c[1], :]
        x0[2, :] .= x[c[2], :]
        xt[1, :] .= x[c[1], :] .+ u[c[1], :]
        xt[2, :] .= x[c[2], :] .+ u[c[2], :]
        centroid = mean(xt; dims=1)
        R1I[:] .= R[c[1], :]
        R1J[:] .= R[c[2], :]
        L0, F0 = _beam_local_frame!(F0, x0, dfes.x1x2_vector[i])
        FtI=R1I*F0;
        FtJ=R1J*F0;
        Ft = (FtI + FtJ) / 2
        for tv in 1:3
            X = fill(0.0, 2) # must allocate here, the scatter3d stores reference to it
            Y = fill(0.0, 2)
            Z = fill(0.0, 2)
            X[1] = centroid[1]
            Y[1] = centroid[2]
            Z[1] = centroid[3]
            X[2] = X[1] .+ triad_length*Ft[1, tv]
            Y[2] = Y[1] .+ triad_length*Ft[2, tv]
            Z[2] = Z[1] .+ triad_length*Ft[3, tv]
            push!(t, scatter3d(;x=X, y=Y, z=Z, mode="lines", line=attr(color=colors[tv], width=lwidth), kwargs...))
        end
    end
    return t
end

end # module
