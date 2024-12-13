# **Terraform-SCV-Jenkins**

Despliegue de una aplicación Python mediante un pipeline de Jenkins.
Despliegue en un contenedor Docker mediante un pipeline de Jenkins.

---
# Índice
* **Dockerfile**
* **Aplicación Python (I-II)**
* **Despligue en contenedor Docker (I-)**
---

## **Dockerfile**
Tal y como hemos aprendido con las diapositivas de la asignatura, para crear la imagen personalizada de Jenkins es:

```Dockerfile
FROM jenkins/jenkins # Imagen oficial de Jenkins disponible en Docker Hub.
USER root            # Cambiamos al usuario root para ejecutar comandos en superusuario.
RUN apt-get update && apt-get install -y lsb-release # Actualizamos repositorios e instalamos lsb-release.
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
https://download.docker.com/linux/debian/gpg usr/share/keyrings/ # Descargamos la clave de docker y la guardamos en el directorio indicado.
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
https://download.docker.com/linux/debian/gpg    # instalamos docker.
RUN echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli # Actualiza los repositorios e instala el cliente de Docker.
USER jenkins # Cambiamos de nuevo al usuario jenkins.
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow" 
# instalamos plugins de jenkins llamados blueocean y docker-workflow enfocados a la integración continua y el despliegue de aplicaciones en contenedores(Docker).

```
---
## **Aplicación Python**
Tras seguir los pasos del tutorial tal y como indica el entregable, hemos optenido el siguiente Pipeline:

```python
pipeline {  # Definición de un pipeline
    agent none  # No se ejecuta en un agente específico
    options {
        skipStagesAfterUnstable() # Omitir etapas después de inestable
    }
    stages {
        stage('Build') { # Etapas de construcción
            agent {
                docker {
                    image 'python:3.12.0-alpine3.18' # Imagen de docker
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'   
                # Compilar archivos
                stash(name: 'compiled-results', includes: 'sources/*.py*')  
                # Almacenar archivos compilados
            }
        }
```
---
## **Aplicación Python (I)**

```python
stage('Test') { # Etapas de pruebas
            agent {
                docker {
                    image 'qnib/pytest' # Imagen de docker
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py' 
                # Ejecutar pruebas unitarias y generar informe
            }
            post {
                always {
                    junit 'test-reports/results.xml' 
                    # Publica los informes de las pruebas unitarias
                }
            }
        }
```
---
## **Aplicación Python (II)**

```python
stage('Deliver') {  # Etapas de entrega
            agent any   # Se ejecuta en cualquier agente
            environment { 
                VOLUME = '$(pwd)/sources:/src'  # Volumen para montar el código fuente
                IMAGE = 'cdrx/pyinstaller-linux:python2'  # Imagen de docker para empaquetar la app
            }
            steps {
                dir(path: env.BUILD_ID) { # Directorio de trabajo
                    unstash(name: 'compiled-results')  # Extraer archivos compilados
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"  
                    #Ejecuta PyInstaller dentro del contenedor Docker para generar un ejecutable independiente.
                }
            }
            post {  # Publica el artefacto
                success {  # Solo se hace si la etapa es exitosa
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" #Archiva el ejecutable generado para su posterior acceso.
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                    # Elimina los directorios de construcción y distribución generados durante el proceso, para limpiar el entorno.
                }
            }
        }
    }
}

```
---
##  **Despligue en contenedor Docker**
El archivo Terraform creado con las indicaciones necesarias para realizar el entregable es el siguiente:
```
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
```
---
##  **Despligue (II)**
* Definimos la red Docker llamada "jenkins-network"
* Usamos dos Volúmenes. Se utilizan para la persistencia de datos entre contenedores.
```
resource "docker_network" "jenkins" {
  name = "jenkins-network"
  # proporciona un aislamiento de red para los contenedores relacionados con Jenkins
}
 "jenkins-docker-certs" y "jenkins-data"
resource "docker_volume" "jenkins_certs" {
  name = "jenkins-docker-certs"
}
resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}
```
---
##  **Despligue (III)**
* Define un contenedor Docker llamado "jenkins-docker" que utiliza la imagen "docker:dind"
* Este contenedor permite ejecutar Docker dentro de Docker (DinD)
```
resource "docker_container" "jenkins_docker" {
  name = "jenkins-docker"
  image = "docker:dind"
  restart = "unless-stopped"
  privileged = true
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]
```
---
##  **Despligue (IV)**
* Define los puertos que se exponen en el contenedor
```
  ports {
    internal = 3000
    external = 3000
  }
  ports {
    internal = 5000
    external = 5000
  }
  # Utilizado comunicación demonio docker (TLS)
  ports {
    internal = 2376
    external = 2376
  }
```
---
##  **Despligue (V)**
* Define los volúmenes que se montan en el contenedor
* Define la red que se utiliza para el contenedor
```
  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }
  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
  networks_advanced {
    name = docker_network.jenkins.name
    aliases = [ "docker" ]
  }
```
---
# **Despliegue (VI)**
* Utiliza la opción --storage-driver para configurar el controlador de almacenamiento el Controlador overlay2 se utiliza para la gestión eficaz de capas y almacenamiento.
```
  command = ["--storage-driver", "overlay2"]
}
```
---
##  **Despligue (VII)**
* Se crea un recurso de tipo 'docker_container' llamado 'jenkins-blueocean'
```
resource "docker_container" "jenkins_blueocean" {
  name = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "unless-stopped"
  env = [
    "DOCKER_HOST=tcp://docker:2376", # Dirección host docker
    "DOCKER_CERT_PATH=/certs/client", # Ruta de certificados
    "DOCKER_TLS_VERIFY=1", # Verificación TLS
  ]
```
---
##  **Despligue (VIII)**
* Define los puertos que se exponen en el contenedor
* Para acceder a la interfaz web de Jenkins Blue Ocean desde el exterior.
* Se utiliza para la comunicación de agentes Jenkins.
``` 
  ports {
    internal = 8080
    external = 8080
  }
  ports {
    internal = 50000
    external = 50000
  }
```
---
##  **Despligue (IX)**

* define los volúmenes que se montan en el contenedor
* configurado de solo lectura, utilizado para proporcionar certificados necesarios.
```
  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
    read_only = true
  }
```
---

##  **Despligue (X)**

* Conecta el contenedor a la red Docker llamada "jenkins"
* Esto permite la comunicación entre contenedores en la misma red.
```
  networks_advanced {
    name = docker_network.jenkins.name 
  }
}
```

