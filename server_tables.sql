use jniqw847exo0xq4a;

-- Спеціальність
CREATE TABLE specialty_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    specialty_name VARCHAR(255) NOT NULL,
    codes JSON
);
-- Аудиторія
CREATE TABLE audience_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    number_of_seats INT CHECK (number_of_seats >= 0),
    audience_number INT NOT NULL,
    building INT NOT NULL
);
-- Групи
CREATE TABLE groups_TB (
    group_code VARCHAR(255) PRIMARY KEY,
    specialty_id INT,
    number_of_students INT CHECK (number_of_students >= 0),
    FOREIGN KEY (specialty_id) REFERENCES specialty_TB(id)
);
-- Вчителі
CREATE TABLE teachers_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    department VARCHAR(255) NOT NULL,
    post ENUM ('Assistant','Teacher','Senior_teacher','Docent','Professor','Unknown')
);
-- Навчальний план

CREATE TABLE curriculum_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    subject_name VARCHAR(255) UNIQUE NOT NULL,
    related_teachers JSON,
    related_groups JSON,
    correspondence BOOL DEFAULT FALSE
);

-- Розклад
CREATE TABLE schedule_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    teachers_list JSON,
    groups_list JSON,
    subject_id INT,
    semester_number ENUM('1','2'),
    week_number ENUM('1','2'),
    day_number ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'),
    pair_number ENUM('1','2','3','4','5','6','7'),
    visit_format ENUM('Offline','Online'),
    lesson_type ENUM('Lecture','Practice','Laboratory'),
    audience INT,
    FOREIGN KEY (subject_id) REFERENCES curriculum_TB(id),
    FOREIGN KEY (audience) REFERENCES audience_TB(id)
);
-- Таблиця зі списком адміністраторів розкладу
CREATE TABLE admin_list_TB (
    id INT AUTO_INCREMENT PRIMARY KEY,
    login VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) 
);