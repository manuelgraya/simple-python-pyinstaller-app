terraform { # configurafión del proveedor de terraform y docker
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"  # version del proveedor minima que debe de utilizar
    }
  }
}
# configura proveedor de docker para terraform interactue con docker
provider "docker" {}  
# define una red Docker llamada "jenkins-network"
resource "docker_network" "jenkins" {
  name = "jenkins-network"
  # proporciona un aislamiento de red para los contenedores relacionados con Jenkins
}
# definen dos volúmenes Docker, "jenkins-docker-certs" y "jenkins-data"
resource "docker_volume" "jenkins_certs" {
  name = "jenkins-docker-certs"
}
# volúmenes se utilizan para persistir datos entre ejecuciones de contenedores.
resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}
# define un contenedor Docker llamado "jenkins-docker" que utiliza la imagen "docker:dind"
# Este contenedor permite ejecutar Docker dentro de Docker (DinD)
resource "docker_container" "jenkins_docker" {
  name = "jenkins-docker"
  image = "docker:dind"
  restart = "unless-stopped"
  privileged = true
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
  # define los puertos que se exponen en el contenedor
  ports {
    internal = 3000
    external = 3000
  }
  ports {
    internal = 5000
    external = 5000
  }
 
  # Este puerto se utiliza para la comunicación con el demonio de Docker 
  # A través del protocolo TLS.
  ports {
    internal = 2376
    external = 2376
  }
  # define los volúmenes que se montan en el contenedor
  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }
  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
  # define la red que se utiliza para el contenedor
  networks_advanced {
    name = docker_network.jenkins.name
    aliases = [ "docker" ]
  }
  # Establece la configuración del comando de inicio del contenedor
  # Utiliza la opción --storage-driver para configurar el controlador de almacenamiento
  # Controlador overlay2 se utiliza para la gestión eficaz de capas y almacenamiento.
  command = ["--storage-driver", "overlay2"]
}
# Se crea un recurso de tipo 'docker_container' llamado 'jenkins-blueocean'
resource "docker_container" "jenkins_blueocean" {
  name = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "unless-stopped"
  env = [
    "DOCKER_HOST=tcp://docker:2376", # Dirección host docker
    "DOCKER_CERT_PATH=/certs/client", # Ruta de certificados
    "DOCKER_TLS_VERIFY=1", # Verificación TLS
  ]
  # define los puertos que se exponen en el contenedor
  # Para acceder a la interfaz web de Jenkins Blue Ocean desde el exterior.
  ports {
    internal = 8080
    external = 8080
  }
 # Se utiliza para la comunicación de agentes Jenkins.
  ports {
    internal = 50000
    external = 50000
  }
  # define los volúmenes que se montan en el contenedor
  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
 
 # configurado de solo lectura, utilizado para proporcionar certificados necesarios.
  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
    read_only = true
  }
 # Conecta el contenedor a la red Docker llamada "jenkins"
 # Esto permite la comunicación entre contenedores en la misma red.
  networks_advanced {
    name = docker_network.jenkins.name 
  }
}