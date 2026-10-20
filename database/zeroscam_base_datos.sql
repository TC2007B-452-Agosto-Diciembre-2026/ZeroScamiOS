CREATE DATABASE IF NOT EXISTS ZeroScam;
USE ZeroScam;

-- 1. Tablas independientes (Sin llaves foráneas)
CREATE TABLE Rol (
    id_rol INT AUTO_INCREMENT PRIMARY KEY,
    nombre_rol VARCHAR(30) NOT NULL UNIQUE COMMENT 'Usuario, Administrador, Policia, Owner',
    descripcion VARCHAR(150) NULL
);

CREATE TABLE Estado (
    id_estado INT AUTO_INCREMENT PRIMARY KEY,
    nombre_estado VARCHAR(30) NOT NULL UNIQUE COMMENT 'RECIBIDO, EN_REVISION, VALIDADO, RECHAZADO, CANALIZADO',
    descripcion VARCHAR(150) NULL,
    es_final BOOLEAN NOT NULL DEFAULT FALSE,
    orden INT NULL
);

CREATE TABLE TipoFraude (
    id_tipo_fraude INT AUTO_INCREMENT PRIMARY KEY,
    nombre_tipo VARCHAR(50) NOT NULL UNIQUE,
    descripcion VARCHAR(255) NULL
);

-- 2. Tabla Usuario (Depende de Rol)
CREATE TABLE Usuario (
    id_usuario BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_rol INT NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    pais VARCHAR(30) NOT NULL,
    correo_electronico VARCHAR(150) NOT NULL UNIQUE,
    contrasena_hash VARCHAR(255) NOT NULL,
    estado_cuenta VARCHAR(20) NOT NULL DEFAULT 'ACTIVO' COMMENT 'ACTIVO, SUSPENDIDO',
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_rol) REFERENCES Rol(id_rol)
);

-- 3. Tabla SitioWeb_URL (Independiente)
CREATE TABLE SitioWeb_URL (
    id_url BIGINT AUTO_INCREMENT PRIMARY KEY,
    url_texto VARCHAR(2048) NOT NULL,
    nivel_riesgo_global VARCHAR(20) NOT NULL DEFAULT 'BAJO' COMMENT 'BAJO, MEDIO, ALTO, MUY_ALTO',
    estado_certificado VARCHAR(50) NULL,
    fecha_ultima_evaluacion TIMESTAMP NULL
);

-- 4. Tabla Reporte (Depende de Usuario, TipoFraude y Estado)
CREATE TABLE Reporte (
    id_reporte BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_usuario BIGINT NOT NULL,
    id_tipo_fraude INT NOT NULL,
    id_estado INT NOT NULL,
    descripcion_incidente TEXT NOT NULL,
    fecha_incidente TIMESTAMP NOT NULL,
    nivel_riesgo_asignado VARCHAR(20) NOT NULL DEFAULT 'NO_EVALUADO',
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_tipo_fraude) REFERENCES TipoFraude(id_tipo_fraude),
    FOREIGN KEY (id_estado) REFERENCES Estado(id_estado),
    INDEX idx_reporte_usuario (id_usuario),
    INDEX idx_reporte_estado (id_estado)
);

-- 5. Tablas dependientes de Reporte y otras
CREATE TABLE Evidencia (
    id_evidencia BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_reporte BIGINT NOT NULL,
    ruta_archivo VARCHAR(500) NOT NULL,
    tipo_archivo VARCHAR(50) NOT NULL,
    fecha_carga TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte)
);

CREATE TABLE Reporte_URL (
    id_reporte BIGINT NOT NULL,
    id_url BIGINT NOT NULL,
    fecha_asociacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_reporte, id_url),
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte),
    FOREIGN KEY (id_url) REFERENCES SitioWeb_URL(id_url)
);

CREATE TABLE Historial_Estado (
    id_historial BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_reporte BIGINT NOT NULL,
    id_admin_responsable BIGINT NOT NULL,
    id_estado_anterior INT NULL COMMENT 'NULL en el registro inicial',
    id_estado_nuevo INT NOT NULL,
    observaciones TEXT NULL,
    fecha_cambio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte),
    FOREIGN KEY (id_admin_responsable) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_estado_anterior) REFERENCES Estado(id_estado),
    FOREIGN KEY (id_estado_nuevo) REFERENCES Estado(id_estado)
);

CREATE TABLE Notificacion_Alerta (
    id_notificacion BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_usuario BIGINT NOT NULL,
    id_reporte BIGINT NULL,
    mensaje TEXT NOT NULL,
    leido_estatus BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_envio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_reporte) REFERENCES Reporte(id_reporte)
);
