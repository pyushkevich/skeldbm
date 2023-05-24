# Using the 2023a build of our utilities as the base
FROM pyushkevich/tk:2023a

# Install python packages
COPY ./requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt

# Copy the contents
COPY . /tk/skeldbm
WORKDIR /tk/skeldbm
