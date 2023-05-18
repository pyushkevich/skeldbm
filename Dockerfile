FROM pyushkevich/cmrep:latest

# Install build tools
RUN apt-get install -y ninja-build

# Download and build greedy
RUN git clone https://github.com/pyushkevich/greedy /tk/greedy/src
RUN cd /tk/greedy/src && git checkout master
RUN mkdir /tk/greedy/build
WORKDIR /tk/greedy/build
RUN cmake \
    -G Ninja \
    -DITK_DIR=/tk/itk/build \
    -DVTK_DIR=/tk/vtk/build \
    /tk/greedy/src
RUN cmake --build . --parallel

# Update ITK with Module_MorphologicalContourInterpolation
WORKDIR /tk/itk/build
RUN cmake -DModule_MorphologicalContourInterpolation=ON .
# RUN cmake --build . --parallel

# Download and build c3d
RUN git clone https://github.com/pyushkevich/c3d /tk/c3d/src
RUN cd /tk/c3d/src && git checkout master
RUN mkdir /tk/c3d/build
WORKDIR /tk/c3d/build
RUN cmake \
    -G Ninja \
    -DITK_DIR=/tk/itk/build \
    /tk/c3d/src
RUN cmake --build . --parallel

# Make sure we can run greedy 
ENV LD_LIBRARY_PATH="/tk/vtk/build/lib"
ENV PATH="/tk/greedy/build:/tk/cmrep/build:/tk/c3d/build:$PATH"
