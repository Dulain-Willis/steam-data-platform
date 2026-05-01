Traefik at a high level sits in front of other services and forwards incoming request to the right place based on routing rules. 

A request could be

Typing a URL in your browser:                                                                                 
You go to https://google.com → your browser sends a GET request to Google's servers asking for the homepage.

Logging into something:
You fill out a login form and hit submit → your browser sends a POST request with your username and password in the body.

Every button click, every page load, every API call — all requests.

HTTP requests all have the same format. For example in this project if I typed in the URL for the Airflow Webserver UI and went to it, I'm sending a request that looks like this. 
```
GET / HTTP/1.1
Host: localhost                                                                                               
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
Accept: text/html,application/xhtml+xml,application/xml
Accept-Language: en-US,en
Connection: keep-alive
```
Airflow then sends back a response:

```
HTTP/1.1 200 OK
Content-Type: text/html
Content-Length: 15432
```
```
<!DOCTYPE html>
<html>
 ... the Airflow UI page ...
</html>
```

That html is what the browser renders into the page so you see the website. The request/response pair is one round trip, and the browser does dozens of these when loading even just a single page. 

However, the path the request makes is a little more convaluded than that. When you send a GET request like the example above created by typing in a Airflow Webserver URL (http://localhost:8080) and going to it there are multiple steps.

It works like this. First, in the compose.yml you define ports for a docker service. For example in this project airflow-webserver looks like this. 

```yaml
  airflow-webserver:
    container_name: airflow-webserver
    <<: *airflow-common
    command: webserver
    ports:
      - "8080:8080"
    labels:
      - traefik.enable=true
    depends_on:
      airflow-init:
        condition: service_completed_successfully
    restart: always
```

Where I've defined ports: 8080:8080, that translates to host:container. This means when you type in that url and press enter, your browser sends the GET request to your own machine's port 8080 (on the left side of 8080:8080). Your machine and the Airflow container are isolated networks but docker acts as the middleman listening for activity on your host machine's port 8080. When it gets the GET request it sends it to port 8080 in the Webserver container (the right side of 8080:8080). Once received it goes back through the same chain. The Airflow Webserver container sends the html to load the webpage to it's own port 8080. Docker as the middleman listens and forwards the response to the host machine's port 8080 and then the brower loads the page. 

So that's the regular world, but what happens when we add traefik to the mix. With traefik it becomes the middleman too, sitting in front of the services you enable to use Traefik and directing traffic to it. Traefik is exposed as 80:80 in docker compose, so do I go to my browser and type in http://localhost:80 to get to the Airflow Webserver UI instead? Well wait, how does traefik know I want to go to Airflow and not my MinIO UI or some other service? 

It knows through routing rules. The two types are PathPrefix and subdomain. I'll show an example of what this looks like in practice using the airflow example again. When I want to go to the Airflow Webserver UI but through Traefik routing me I have two options. 

Host - Subdomain
http://airflow.localhost

PathPrefix - Path
http://localhost/airflow


You get to define what those are. Also, notice there's no :80 at the end of the URL. That's only because for http 80 is the default, so putting nothing makes the browswer assume port 80. 

Since this project uses docker compose you'd set it in there using a labels key. I'll give an example below using the both methods. Below is what you'd add to your airflow-webserver service definition in your compose.yml

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.airflow.rule=Host(`airflow.localhost`)"
  - "traefik.http.services.airflow.loadbalancer.server.port=8080"
```
```yaml
labels:
  - "traefik.enable=true"                                                                                     
  - "traefik.http.routers.airflow.rule=PathPrefix(`/airflow`)"
  - "traefik.http.services.airflow.loadbalancer.server.port=8080" 
```

The first label simply says I want to opt in this container for traefik being able to route to it. The second label creates a router called airflow. A router is just an internal object to Traefik that says when a request looks like X send it to Y, so by adding the label Traefik makes a rule when a request arrives with Host: airflow.localhost this router claims it and takes care of it. The third label creates a service which which tells Traefik, where do I send the request that I get? So, the router claims request that come in with the defined host name and the service sends it to the right port. 

Thinking about the same flow of a request from earlier we'll do the same thing, but now with Traefik. With all the labels set up, NOW you can go and type http://airflow.localhost. When you do this your browser sends the same GET request from earlier, but to the host machine's port 80. Docker is listening due defining port 80:80 for the Traefik service in the compose.yml and sends the request to port 80 inside the Traefik container. The router named airflow claims the request and the service named airflow sends it directly to port 8080 inside the Airflow Webserver container through the internal docker network. Then just like before the response follows the same chain backwards. Airflow sends the response to port 80 inside the Traefik container across the internal docker network. Traefik sends it back to docker which sends it back to your host machine's port 80 so the browser can then render the Airflow Webserver UI.

So first, when you set up Traefik as a docker service you need to mount `docker.sock`. That is the Docker control socket. A socket is...... It's located at /var/run/docker.sock and it's created when the Docker daemon starts, meaning when you open docker desktop and the internal Docker engine starts, or when you start the docker service on linux in the terminal with `sudo service docker start`. Although it has a file path it is not a file. You can see this by running a command like

```
ls -l /var/run/docker.sock
```
when you do this you'll something like
```
srw-rw---- 1 root docker 0 Apr 29 12:00 /var/run/docker.sock
```
It starts with an s where as a normal file would start with a -
```
-rw-r--r-- some-file.txt
```
and a directory would start with a d
```
drwxr-xr-x some-folder
```
If you were to try to open or read it with a command like `cat /var/run/docker.sock` it wouldn't do anything useful. So, whenn you add the mount to the compose.yml

```yaml
- /var/run/docker.sock:/var/run/docker.sock:ro
```

the left side is the socket on your host machine and the right side is where that same socket appears inside the Traefik container. Once Traefik can see that socket, it can ask Docker questions like "what containers are running?", "what labels do they have?", "what networks are they on?", and "what ports are they exposing?". Going back to the Airflow Webserver UI example, mounting the docker socket allows Traefik to learn "when I see airflow.localhost, I should send that request to the airflow container on port 8080." Then when the real request comes in from the browser, Traefik already knows what to do with it.











Traefik on docker so when using providers.docker enables exposing containers by default. So it'll go through and find what ports containers use because by default providers.docker.exposedByDefault="true". You can set it false but then you'll have to add a labels: to a docker service with traefik.enable=true for what you want exposed. Services that don't have ports like mc and spark-worker for this project will error out so you just add traefik.enables="false" under labels: in the service in the compose.yaml

