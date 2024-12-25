-- Процедури для таблиці 'Навчальний план'

DELIMITER //

-- Видаляє дублікати 

CREATE PROCEDURE removing_duplicates_curriculum(INOUT groups_json JSON, INOUT teachers_json JSON)
BEGIN
    -- Перевіряємо, чи містить groups_json дані
    IF JSON_LENGTH(groups_json) > 0 THEN
        -- Оновлюємо groups_json, залишаючи лише унікальні записи за полем "code"
        SET groups_json = (
            SELECT JSON_ARRAYAGG(value)
            FROM (
                -- Вибираємо значення з JSON та додаємо порядковий номер (pos)
                SELECT value
                FROM (
                    SELECT 
                        value,
                        ROW_NUMBER() OVER (
                            -- Розділяємо записи за полем "code" та сортуємо за порядковим номером у зворотньому порядку
                            PARTITION BY JSON_UNQUOTE(JSON_EXTRACT(value, '$.code'))
                            ORDER BY pos DESC
                        ) AS rn
                    FROM JSON_TABLE(groups_json, '$[*]' COLUMNS (pos FOR ORDINALITY, value JSON PATH '$')) AS jt
                ) AS ranked
                -- Залишаємо лише перший запис для кожного унікального "code"
                WHERE rn = 1
            ) AS unique_values
        );
    END IF;

    -- Перевіряємо, чи містить teachers_json дані
    IF JSON_LENGTH(teachers_json) > 0 THEN
        -- Оновлюємо teachers_json, залишаючи лише унікальні записи за полем "id"
        SET teachers_json = (
            SELECT JSON_ARRAYAGG(value)
            FROM (
                -- Вибираємо значення з JSON та додаємо порядковий номер (pos)
                SELECT value
                FROM (
                    SELECT 
                        value,
                        ROW_NUMBER() OVER (
                            -- Розділяємо записи за полем "id" та сортуємо за порядковим номером у зворотньому порядку
                            PARTITION BY JSON_UNQUOTE(JSON_EXTRACT(value, '$.id'))
                            ORDER BY pos DESC
                        ) AS rn
                    FROM JSON_TABLE(teachers_json, '$[*]' COLUMNS (pos FOR ORDINALITY, value JSON PATH '$')) AS jt
                ) AS ranked
                -- Залишаємо лише перший запис для кожного унікального "id"
                WHERE rn = 1
            ) AS unique_values
        );
    END IF;
END //

-- Перевірка наявності груп та вчителів в таблицях 'Групи', 'Вчителі'
CREATE PROCEDURE check_gr_th_existence(IN groups_json JSON, IN teachers_json JSON, OUT result VARCHAR(255))
check_gr_th_existence: BEGIN
    DECLARE group_name VARCHAR(255);
    DECLARE teacher_id VARCHAR(255);
    DECLARE group_exists INT DEFAULT 0;
    DECLARE teacher_exists INT DEFAULT 0;
    DECLARE i INT DEFAULT 0;
    DECLARE j INT DEFAULT 0;

    -- Перевірка наявності груп
    WHILE i < JSON_LENGTH(groups_json) DO
        SET group_name = JSON_UNQUOTE(JSON_EXTRACT(groups_json, CONCAT('$[', i, '].code')));
        SELECT COUNT(*) INTO group_exists FROM groups_TB WHERE group_code = group_name;

        IF group_exists = 0 THEN
            SET result = CONCAT('Група ', group_name, ' не існує');
            LEAVE check_gr_th_existence;
        END IF;

        SET i = i + 1;
    END WHILE;

    -- Перевірка наявності вчителів
    WHILE j < JSON_LENGTH(teachers_json) DO
        SET teacher_id = JSON_UNQUOTE(JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].id')));
        SELECT COUNT(*) INTO teacher_exists FROM teachers_TB WHERE id = teacher_id;

        IF teacher_exists = 0 THEN
            SET result = CONCAT('Вчитель з id ', teacher_id, ' не існує');
            LEAVE check_gr_th_existence;
        END IF;

        SET j = j + 1;
    END WHILE;

    -- Якщо всі групи та вчителі існують
    SET result = 'ОК';

END //

-- Перевіряє чи не видаляємо ми групу чи вчителя які є в розкладі
CREATE PROCEDURE check_schedule_existence(IN id INT, IN old_groups_json JSON, IN old_teachers_json JSON, IN new_groups_json JSON, IN new_teachers_json JSON, OUT result VARCHAR(255))
BEGIN
    DECLARE old_group_name VARCHAR(255);
    DECLARE old_teacher_id int;
    DECLARE new_group_name VARCHAR(255);
    DECLARE new_teacher_id int;
    DECLARE i INT DEFAULT 0;
    DECLARE j INT DEFAULT 0;
    DECLARE k INT DEFAULT 0;
    DECLARE l INT DEFAULT 0;
    DECLARE old_existing_groups TEXT DEFAULT '';
    DECLARE new_existing_groups TEXT DEFAULT '';
    DECLARE dif_existing_groups TEXT DEFAULT '';
    DECLARE old_existing_teachers TEXT DEFAULT '';
    DECLARE new_existing_teachers TEXT DEFAULT '';
    DECLARE dif_existing_teachers TEXT DEFAULT '';

    -- Перелік старих груп що наявні в розкладі
    WHILE i < JSON_LENGTH(old_groups_json) DO
        SET old_group_name = JSON_UNQUOTE(JSON_EXTRACT(old_groups_json, CONCAT('$[', i, '].code')));
        IF EXISTS (SELECT 1 FROM schedule_TB WHERE JSON_CONTAINS(groups_list, JSON_QUOTE(old_group_name)) AND subject_id = id) THEN
            SET old_existing_groups = CONCAT(old_existing_groups, old_group_name, ', ');
        END IF;
        SET i = i + 1;
    END WHILE;
    
    -- Перелік нових груп що наявні в розкладі
    WHILE j < JSON_LENGTH(new_groups_json) DO
        SET new_group_name = JSON_UNQUOTE(JSON_EXTRACT(new_groups_json, CONCAT('$[', j, '].code')));
        IF EXISTS (SELECT 1 FROM schedule_TB WHERE JSON_CONTAINS(groups_list, JSON_QUOTE(new_group_name)) AND subject_id = id) THEN
            SET new_existing_groups = CONCAT(new_existing_groups, new_group_name, ', ');
        END IF;
        SET j = j + 1;
    END WHILE;

    -- Переік старих вчителів що наявні в розкладі
    WHILE k < JSON_LENGTH(old_teachers_json) DO
        SET old_teacher_id = JSON_UNQUOTE(JSON_EXTRACT(old_teachers_json, CONCAT('$[', k, '].id')));
        IF EXISTS (SELECT 1 FROM schedule_TB WHERE JSON_CONTAINS(teachers_list, JSON_OBJECT('id', old_teacher_id)) AND subject_id = id) THEN
            SET old_existing_teachers = CONCAT(old_existing_teachers, old_teacher_id, ', ');
        END IF;
        SET k = k + 1;
    END WHILE;
    
    -- Перелік нових вчителів що наявні в розкладі
    WHILE l < JSON_LENGTH(new_teachers_json) DO
        SET new_teacher_id = JSON_UNQUOTE(JSON_EXTRACT(new_teachers_json, CONCAT('$[', l, '].id')));
        IF EXISTS (SELECT 1 FROM schedule_TB WHERE JSON_CONTAINS(teachers_list, JSON_OBJECT('id', new_teacher_id)) AND subject_id = id) THEN
            SET new_existing_teachers = CONCAT(new_existing_teachers, new_teacher_id, ', ');
        END IF;
        SET l = l + 1;
    END WHILE;

    -- Формування результату
    IF new_existing_teachers LIKE CONCAT('%', old_existing_teachers, '%') AND new_existing_groups LIKE CONCAT('%', old_existing_groups, '%') THEN
        SET result = 'ОК';
    ELSE
    set dif_existing_groups = REPLACE(old_existing_groups, new_existing_groups, '');
    set dif_existing_teachers = REPLACE(old_existing_teachers, new_existing_teachers, '');
        SET result = CONCAT('Групи в розкладі: ', TRIM(TRAILING ', ' FROM dif_existing_groups), '; Вчителі в розкладі з ID: ', TRIM(TRAILING ', ' FROM dif_existing_teachers));
    END IF;

END //

-- Перевіряє відповідність запланованих та розподілених пар
CREATE PROCEDURE check_correspondence(IN groups_json JSON, IN teachers_json JSON, OUT result BOOL)
check_correspondence: BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE j INT DEFAULT 0;
    DECLARE group_planned_lectures INT;
    DECLARE group_planned_practicals INT;
    DECLARE group_planned_labs INT;
    DECLARE group_scheduled_lectures INT;
    DECLARE group_scheduled_practicals INT;
    DECLARE group_scheduled_labs INT;
    DECLARE teacher_planned_lectures INT;
    DECLARE teacher_planned_practicals INT;
    DECLARE teacher_planned_labs INT;
    DECLARE teacher_scheduled_lectures INT;
    DECLARE teacher_scheduled_practicals INT;
    DECLARE teacher_scheduled_labs INT;

    -- Перевірка груп
    WHILE i < JSON_LENGTH(groups_json) DO
        SET group_planned_lectures = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].planned_lectures'));
        SET group_planned_practicals = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].planned_practicals'));
        SET group_planned_labs = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].planned_labs'));
        SET group_scheduled_lectures = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].scheduled_lectures'));
        SET group_scheduled_practicals = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].scheduled_practicals'));
        SET group_scheduled_labs = JSON_EXTRACT(groups_json, CONCAT('$[', i, '].scheduled_labs'));

        IF group_planned_lectures != group_scheduled_lectures OR
           group_planned_practicals != group_scheduled_practicals OR
           group_planned_labs != group_scheduled_labs THEN
            SET result = FALSE;
            LEAVE check_correspondence;
        END IF;

        SET i = i + 1;
    END WHILE;

    -- Перевірка вчителів
    WHILE j < JSON_LENGTH(teachers_json) DO
        SET teacher_planned_lectures = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].planned_lectures'));
        SET teacher_planned_practicals = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].planned_practicals'));
        SET teacher_planned_labs = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].planned_labs'));
        SET teacher_scheduled_lectures = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].scheduled_lectures'));
        SET teacher_scheduled_practicals = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].scheduled_practicals'));
        SET teacher_scheduled_labs = JSON_EXTRACT(teachers_json, CONCAT('$[', j, '].scheduled_labs'));

        IF teacher_planned_lectures != teacher_scheduled_lectures OR
           teacher_planned_practicals != teacher_scheduled_practicals OR
           teacher_planned_labs != teacher_scheduled_labs THEN
            SET result = FALSE;
            LEAVE check_correspondence;
        END IF;

        SET j = j + 1;
    END WHILE;

    -- Якщо всі значення відповідають
    SET result = TRUE;

END //

-- Функція для ініціалізації групи
CREATE FUNCTION initGroup(
    id INT,
    group_name VARCHAR(255),
    new_planned_lectures INT,
    new_planned_practicals INT,
    new_planned_labs INT
) RETURNS JSON DETERMINISTIC
BEGIN
    DECLARE scheduled_lectures INT DEFAULT 0;
    DECLARE scheduled_practicals INT DEFAULT 0;
    DECLARE scheduled_labs INT DEFAULT 0;

    -- Підраховуємо заплановані лекції
    SELECT COUNT(*) INTO scheduled_lectures
    FROM schedule_TB
    WHERE subject_id = id
    AND JSON_CONTAINS(groups_list, JSON_QUOTE(group_name))
    AND lesson_type = 'Lecture';

    -- Підраховуємо заплановані практичні
    SELECT COUNT(*) INTO scheduled_practicals
    FROM schedule_TB
    WHERE subject_id = id
    AND JSON_CONTAINS(groups_list, JSON_QUOTE(group_name))
    AND lesson_type = 'Practice';

    -- Підраховуємо заплановані лабораторні
    SELECT COUNT(*) INTO scheduled_labs
    FROM schedule_TB
    WHERE subject_id = id
    AND JSON_CONTAINS(groups_list, JSON_QUOTE(group_name))
    AND lesson_type = 'Laboratory';

    -- Створюємо новий об'єкт групи з запланованими парами
    RETURN JSON_OBJECT(
        'code', group_name,
        'planned_lectures', new_planned_lectures,
        'planned_practicals', new_planned_practicals,
        'planned_labs', new_planned_labs,
        'scheduled_lectures', scheduled_lectures,
        'scheduled_practicals', scheduled_practicals,
        'scheduled_labs', scheduled_labs
    );
END //

-- Функція для ініціалізації вчителя
DELIMITER //
CREATE FUNCTION initTeacher(
    curriculum_id INT,
    teacher_id INT,
    new_planned_lectures INT,
    new_planned_practicals INT,
    new_planned_labs INT
) RETURNS JSON DETERMINISTIC
BEGIN
    DECLARE scheduled_lectures INT DEFAULT 0;
    DECLARE scheduled_practicals INT DEFAULT 0;
    DECLARE scheduled_labs INT DEFAULT 0;
    DECLARE teachers_name VARCHAR(255);

    -- Отримуємо ім'я вчителя за його id
    SELECT full_name INTO teachers_name
    FROM teachers_TB
    WHERE id = teacher_id
    LIMIT 1;

    -- Підраховуємо заплановані лекції
    SELECT COUNT(*) INTO scheduled_lectures
    FROM schedule_TB
    WHERE subject_id = curriculum_id
    AND JSON_CONTAINS(teachers_list, JSON_OBJECT('id', teacher_id, 'name', teachers_name))
    AND lesson_type = 'Lecture';

    -- Підраховуємо заплановані практичні
    SELECT COUNT(*) INTO scheduled_practicals
    FROM schedule_TB
    WHERE subject_id = curriculum_id
    AND JSON_CONTAINS(teachers_list, JSON_OBJECT('id', teacher_id, 'name', teachers_name))
    AND lesson_type = 'Practice';

    -- Підраховуємо заплановані лабораторні
    SELECT COUNT(*) INTO scheduled_labs
    FROM schedule_TB
    WHERE subject_id = curriculum_id
    AND JSON_CONTAINS(teachers_list, JSON_OBJECT('id', teacher_id, 'name', teachers_name))
    AND lesson_type = 'Laboratory';

    -- Створюємо новий об'єкт вчителя з запланованими парами
    RETURN JSON_OBJECT(
        'id', teacher_id,
        'name', teachers_name,
        'planned_lectures', new_planned_lectures,
        'planned_practicals', new_planned_practicals,
        'planned_labs', new_planned_labs,
        'scheduled_lectures', scheduled_lectures,
        'scheduled_practicals', scheduled_practicals,
        'scheduled_labs', scheduled_labs
    );
END //

DELIMITER ;

-- Процедури для таблиці 'Розклад'

DELIMITER //

-- Видаляє дублікати

DELIMITER //

CREATE PROCEDURE removing_duplicates_schedule_TB(INOUT groups_json JSON, INOUT teachers_json JSON)
BEGIN
    -- Перевіряємо, чи містить groups_json дані
    IF JSON_LENGTH(groups_json) > 0 THEN
        -- Оновлюємо groups_json, залишаючи лише унікальні записи
        SET groups_json = (
            SELECT JSON_ARRAYAGG(value)
            FROM (
                -- Вибираємо унікальні значення з JSON
                SELECT DISTINCT JSON_UNQUOTE(value) AS value
                FROM JSON_TABLE(groups_json, '$[*]' COLUMNS (value JSON PATH '$')) AS jt
            ) AS unique_values
        );
    END IF;

    -- Перевіряємо, чи містить teachers_json дані
    IF JSON_LENGTH(teachers_json) > 0 THEN
        -- Оновлюємо teachers_json, залишаючи лише унікальні записи
        SET teachers_json = (
            SELECT JSON_ARRAYAGG(value)
            FROM (
                -- Вибираємо унікальні об'єкти з JSON, перетворюючи id на UNSIGNED
                SELECT DISTINCT JSON_OBJECT(
                    'id', CAST(JSON_UNQUOTE(JSON_EXTRACT(value, '$.id')) AS UNSIGNED),
                    'name', JSON_UNQUOTE(JSON_EXTRACT(value, '$.name'))
                ) AS value
                FROM JSON_TABLE(teachers_json, '$[*]' COLUMNS (value JSON PATH '$')) AS jt
            ) AS unique_values
        );
    END IF;
END //

-- Перевіряє чи всі групи та вчителі є в плані
CREATE PROCEDURE check_in_curriculum(IN groups_json JSON, IN teachers_json JSON, IN subject_id INT, OUT result VARCHAR(255))
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE group_code VARCHAR(255);
    DECLARE teacher_id INT;
    DECLARE teacher_name VARCHAR(255);
    DECLARE existing_groups_count INT DEFAULT 0;
    DECLARE existing_teachers_count INT DEFAULT 0;

    -- Перевірка груп
    WHILE i < JSON_LENGTH(groups_json) DO
        SET group_code = JSON_UNQUOTE(JSON_EXTRACT(groups_json, CONCAT('$[', i, ']')));
        IF EXISTS (SELECT 1 FROM curriculum_TB WHERE id = subject_id AND JSON_CONTAINS(related_groups, CONCAT('{"code":"', group_code, '"}'))) THEN
            SET existing_groups_count = existing_groups_count + 1;
        END IF;
        SET i = i + 1;
    END WHILE;

    SET i = 0;

    -- Перевірка вчителів
    WHILE i < JSON_LENGTH(teachers_json) DO
        SET teacher_id = JSON_UNQUOTE(JSON_EXTRACT(teachers_json, CONCAT('$[', i, '].id')));
        SET teacher_name = JSON_UNQUOTE(JSON_EXTRACT(teachers_json, CONCAT('$[', i, '].name')));
        IF EXISTS (SELECT 1 FROM curriculum_TB WHERE id = subject_id AND JSON_CONTAINS(related_teachers, CONCAT('{"id":', teacher_id, ',"name":"', teacher_name, '"}'))) THEN
            SET existing_teachers_count = existing_teachers_count + 1;
        END IF;
        SET i = i + 1;
    END WHILE;

    -- Формування результату
    IF existing_groups_count = JSON_LENGTH(groups_json) AND existing_teachers_count = JSON_LENGTH(teachers_json) THEN
        SET result = 'ОК';
    ELSE
        SET result = CONCAT('Деякі групи або вчителі відсутні в плані, кількість груп: ', JSON_LENGTH(groups_json) - existing_groups_count, ' ,кількість вчителів: ',  JSON_LENGTH(teachers_json) - existing_teachers_count);
    END IF;
END //


DELIMITER //

CREATE PROCEDURE update_scheduled_lessons(
    IN groups_list JSON,
    IN teachers_list JSON,
    IN lesson_type VARCHAR(255),
    IN subject_id INT,
    IN is_adding BOOL
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE teacher_id INT;
    DECLARE group_code VARCHAR(255);
    DECLARE teacher_json JSON;
    DECLARE group_json JSON;
    DECLARE scheduled_lectures INT;
    DECLARE scheduled_practicals INT;
    DECLARE scheduled_labs INT;
    DECLARE step INT;
    
    IF is_adding THEN
        SET step = 1;
    ELSE
        SET step = -1;
    END IF;

    -- Обробка вчителів
    WHILE i < JSON_LENGTH(teachers_list) DO
        SET teacher_id = JSON_UNQUOTE(JSON_EXTRACT(teachers_list, CONCAT('$[', i, '].id')));

        -- Отримуємо JSON-об'єкт вчителя з curriculum_TB
        SELECT JSON_EXTRACT(related_teachers, CONCAT('$[', i, ']')) INTO teacher_json
        FROM curriculum_TB
        WHERE id = subject_id;

        -- Оновлюємо кількість запланованих занять
        IF lesson_type = 'Lecture' THEN
            SET scheduled_lectures = JSON_EXTRACT(teacher_json, '$.scheduled_lectures') + step;
            SET teacher_json = JSON_SET(teacher_json, '$.scheduled_lectures', scheduled_lectures);
        ELSEIF lesson_type = 'Practice' THEN
            SET scheduled_practicals = JSON_EXTRACT(teacher_json, '$.scheduled_practicals') + step;
            SET teacher_json = JSON_SET(teacher_json, '$.scheduled_practicals', scheduled_practicals);
        ELSEIF lesson_type = 'Laboratory' THEN
            SET scheduled_labs = JSON_EXTRACT(teacher_json, '$.scheduled_labs') + step;
            SET teacher_json = JSON_SET(teacher_json, '$.scheduled_labs', scheduled_labs);
        END IF;

        -- Оновлюємо JSON-об'єкт вчителя в curriculum_TB
        UPDATE curriculum_TB
        SET related_teachers = JSON_SET(related_teachers, CONCAT('$[', i, ']'), teacher_json)
        WHERE id = subject_id;

        SET i = i + 1;
    END WHILE;

    SET i = 0;

    -- Обробка груп
    WHILE i < JSON_LENGTH(groups_list) DO
        SET group_code = JSON_UNQUOTE(JSON_EXTRACT(groups_list, CONCAT('$[', i, ']')));

        -- Отримуємо JSON-об'єкт групи з curriculum_TB
        SELECT JSON_EXTRACT(related_groups, CONCAT('$[', i, ']')) INTO group_json
        FROM curriculum_TB
        WHERE id = subject_id;

        -- Оновлюємо кількість запланованих занять
        IF lesson_type = 'Lecture' THEN
            SET scheduled_lectures = JSON_EXTRACT(group_json, '$.scheduled_lectures') + step;
            SET group_json = JSON_SET(group_json, '$.scheduled_lectures', scheduled_lectures);
        ELSEIF lesson_type = 'Practice' THEN
            SET scheduled_practicals = JSON_EXTRACT(group_json, '$.scheduled_practicals') + step;
            SET group_json = JSON_SET(group_json, '$.scheduled_practicals', scheduled_practicals);
        ELSEIF lesson_type = 'Laboratory' THEN
            SET scheduled_labs = JSON_EXTRACT(group_json, '$.scheduled_labs') + step;
            SET group_json = JSON_SET(group_json, '$.scheduled_labs', scheduled_labs);
        END IF;

        -- Оновлюємо JSON-об'єкт групи в curriculum_TB
        UPDATE curriculum_TB
        SET related_groups = JSON_SET(related_groups, CONCAT('$[', i, ']'), group_json)
        WHERE id = subject_id;

        SET i = i + 1;
    END WHILE;
END //

-- Перевірка наявності місць в аудиторії
CREATE PROCEDURE check_audience_capacity(
    IN audience INT, 
    IN groups_list JSON, 
    OUT result VARCHAR(255)
)
check_audience_capacity: BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE cur_group_code VARCHAR(255);
    DECLARE students_count INT DEFAULT 0;
    DECLARE total_students INT DEFAULT 0;
    DECLARE audience_capacity INT;

    
    IF audience IS NULL THEN
        SET result = 'ОК';
        LEAVE check_audience_capacity;
    END IF;

    -- Отримуємо вмістимість аудиторії
    SELECT number_of_seats INTO audience_capacity
    FROM audience_TB
    WHERE id = audience;

    -- Проходимося по всім групам та просумуємо їх number_of_students
    WHILE i < JSON_LENGTH(groups_list) DO
        SET cur_group_code = JSON_UNQUOTE(JSON_EXTRACT(groups_list, CONCAT('$[', i, ']')));

        SELECT number_of_students INTO students_count
        FROM groups_TB
        WHERE group_code = cur_group_code;

        SET total_students = total_students + students_count;

        SET i = i + 1;
    END WHILE;

    -- Перевіряємо, чи сума студентів менше за вмістимість аудиторії
    IF total_students <= audience_capacity THEN
        SET result = 'ОК';
    ELSE
        SET result = CONCAT('Перевищення на ', total_students - audience_capacity, ' студентів');
    END IF;
END //

CREATE PROCEDURE check_schedule_conflict(
    IN id INT, 
    IN is_update BOOL,
    IN groups_json JSON, 
    IN teachers_json JSON, 
    IN semester ENUM('1','2'), 
    IN week ENUM('1','2'), 
    IN day ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'), 
    IN pair ENUM('1','2','3','4','5','6','7'),
    OUT result VARCHAR(255)
)
check_schedule_conflict: BEGIN
    DECLARE conflict_exists INT DEFAULT 0;
    DECLARE conflict_message VARCHAR(255);

    -- Перевірка на конфлікт для груп
    SELECT COUNT(*) INTO conflict_exists
    FROM schedule_TB
    WHERE EXISTS (
        SELECT *
        FROM JSON_TABLE(groups_json, '$[*]' COLUMNS (group_code VARCHAR(255) PATH '$')) AS jt
        WHERE JSON_CONTAINS(schedule_TB.groups_list, CONCAT('"', jt.group_code, '"'))
    )
    AND subject_id = id -- Перевіряємо конфлікти тільки для того ж самого предмета
    AND semester_number = semester
    AND week_number = week
    AND day_number = day
    AND pair_number = pair
    AND (is_update = FALSE OR schedule_TB.subject_id != id); -- Враховуємо, що ми можемо редагувати іншу пару

    IF conflict_exists > 0 THEN
        SET result = 'Конфлікт для груп: Група вже має пару з цього предмета в цей час.';
        LEAVE check_schedule_conflict;
    END IF;

    -- Перевірка на конфлікт для вчителів
    SELECT COUNT(*) INTO conflict_exists
    FROM schedule_TB
    WHERE EXISTS (
        SELECT *
        FROM JSON_TABLE(teachers_json, '$[*]' COLUMNS (teacher_id INT PATH '$.id')) AS jt
        WHERE JSON_CONTAINS(schedule_TB.teachers_list, JSON_OBJECT('id', jt.teacher_id))
    )
    AND semester_number = semester
    AND week_number = week
    AND day_number = day
    AND pair_number = pair
    AND (is_update = FALSE OR schedule_TB.subject_id != id); -- Враховуємо, що ми можемо редагувати іншу пару

    IF conflict_exists > 0 THEN
        SET result = 'Конфлікт для вчителів: Вчитель вже має пару в цей час.';
        LEAVE check_schedule_conflict;
    END IF;

    -- Якщо конфліктів немає
    SET result = 'ОК';
END //

DELIMITER ;

-- Процедури для таблиці 'Вчителі'

DELIMITER //

-- Перевірка наявності в плані
CREATE PROCEDURE check_teacher_in_curriculum(
    IN teacher_id INT,
    OUT result VARCHAR(255)
)
BEGIN
    DECLARE teacher_exists INT DEFAULT 0;

    -- Перевірка, чи є вчитель в навчальному плані
    SELECT COUNT(*) INTO teacher_exists
    FROM curriculum_TB
    WHERE JSON_CONTAINS(related_teachers, JSON_OBJECT('id', teacher_id));

    IF teacher_exists > 0 THEN
        SET result = 'Вчитель є в навчальному плані.';
    ELSE
        SET result = 'ОК';
    END IF;
END //

-- Оновлення ім'я вчителя
CREATE PROCEDURE update_teacher(
    IN old_teacher_id INT,
    IN new_teacher_id INT,
    IN new_teacher_name VARCHAR(255)
)
BEGIN
    -- Встановлюємо змінну для тимчасового вимкнення тригера
    SET @disable_trigger = 1;

    -- Оновлення вчителя в таблиці curriculum_TB
    UPDATE curriculum_TB
    SET related_teachers = (
        SELECT JSON_ARRAYAGG(
            CASE
                -- Якщо id вчителя збігається з old_teacher_id, оновлюємо його id та ім'я
                WHEN JSON_EXTRACT(teacher, '$.id') = old_teacher_id THEN JSON_SET(teacher, '$.id', new_teacher_id, '$.name', new_teacher_name)
                -- Інакше залишаємо без змін
                ELSE teacher
            END
        )
        FROM JSON_TABLE(related_teachers, '$[*]' COLUMNS (teacher JSON PATH '$')) AS jt
    )
    -- Фільтруємо записи, де є вчитель з old_teacher_id
    WHERE JSON_CONTAINS(related_teachers, JSON_OBJECT('id', old_teacher_id));

    -- Оновлення вчителя в таблиці schedule_TB
    UPDATE schedule_TB
    SET teachers_list = (
        SELECT JSON_ARRAYAGG(
            CASE
                -- Якщо id вчителя збігається з old_teacher_id, оновлюємо його id та ім'я
                WHEN JSON_EXTRACT(teacher, '$.id') = old_teacher_id THEN JSON_SET(teacher, '$.id', new_teacher_id, '$.name', new_teacher_name)
                -- Інакше залишаємо без змін
                ELSE teacher
            END
        )
        FROM JSON_TABLE(teachers_list, '$[*]' COLUMNS (teacher JSON PATH '$')) AS jt
    )
    -- Фільтруємо записи, де є вчитель з old_teacher_id
    WHERE JSON_CONTAINS(teachers_list, JSON_OBJECT('id', old_teacher_id));

    -- Скидаємо змінну для тимчасового вимкнення тригера
    SET @disable_trigger = NULL;
END //

DELIMITER ;

-- Процедури для таблиці 'Групи'

DELIMITER //

-- Перевірка, чи є група в навчальному плані
CREATE PROCEDURE check_group_in_curriculum(
    IN group_code VARCHAR(255),
    OUT result VARCHAR(255)
)
BEGIN
    DECLARE group_exists INT DEFAULT 0;

    -- Перевірка наявності групи в навчальному плані
    SELECT COUNT(*) INTO group_exists
    FROM curriculum_TB
    WHERE JSON_CONTAINS(related_groups, JSON_OBJECT('code', group_code));

    -- Формування результату
    IF group_exists > 0 THEN
        SET result = 'Група є в навчальному плані.';
    ELSE
        SET result = 'ОК';
    END IF;
END //

-- Оновлення коду групи в плані та розкладі
CREATE PROCEDURE update_group(
    IN old_group_code VARCHAR(255),
    IN new_group_code VARCHAR(255)
)
BEGIN
    -- Встановлюємо змінну для тимчасового вимкнення тригера
    SET @disable_trigger = 1;

    -- Оновлення групи в таблиці curriculum_TB
    UPDATE curriculum_TB
    SET related_groups = (
        SELECT JSON_ARRAYAGG(
            CASE
                -- Якщо код групи збігається з old_group_code, оновлюємо його на new_group_code
                WHEN JSON_EXTRACT(`group`, '$.code') = old_group_code THEN JSON_SET(`group`, '$.code', new_group_code)
                -- Інакше залишаємо без змін
                ELSE `group`
            END
        )
        FROM JSON_TABLE(related_groups, '$[*]' COLUMNS (`group` JSON PATH '$')) AS jt
    )
    -- Фільтруємо записи, де є група з old_group_code
    WHERE JSON_CONTAINS(related_groups, JSON_OBJECT('code', old_group_code));

    -- Оновлення групи в таблиці schedule_TB
    UPDATE schedule_TB
    SET groups_list = (
        SELECT JSON_ARRAYAGG(
            CASE
                -- Якщо код групи збігається з old_group_code, оновлюємо його на new_group_code
                WHEN `group` = old_group_code THEN new_group_code
                -- Інакше залишаємо без змін
                ELSE `group`
            END
        )
        FROM JSON_TABLE(groups_list, '$[*]' COLUMNS (`group` VARCHAR(255) PATH '$')) AS jt
    )
    -- Фільтруємо записи, де є група з old_group_code
    WHERE JSON_CONTAINS(groups_list, JSON_QUOTE(old_group_code));

    -- Скидаємо змінну для тимчасового вимкнення тригера
    SET @disable_trigger = NULL;
END //

-- Перевірка перевищення кількості студентів над кількістю місць при оновленні групи
CREATE PROCEDURE check_group_capacity(
    IN this_group_code VARCHAR(255),
    IN new_number_of_students INT,
    OUT result VARCHAR(255)
)
BEGIN
    DECLARE this_audience_capacity INT;
    DECLARE audience_capacity INT;
    DECLARE total_students INT DEFAULT 0;
    DECLARE cur_group_code VARCHAR(255);
    DECLARE this_groups_list JSON;
    DECLARE i INT DEFAULT 0;
    DECLARE audience_id INT;
    DECLARE done INT DEFAULT 0;

    -- Оголошення курсора для вибірки записів з таблиці schedule_TB
    DECLARE cur CURSOR FOR
        SELECT groups_list, audience
        FROM schedule_TB
        WHERE JSON_CONTAINS(groups_list, JSON_QUOTE(this_group_code));

    -- Обробник подій для завершення курсора
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Відкриття курсора
    OPEN cur;

    -- Цикл для обробки даних курсора
    read_loop: LOOP
        -- Вибірка даних з курсора
        FETCH cur INTO this_groups_list, audience_id;

        -- Якщо курсор завершив вибірку, виходимо з циклу
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Ініціалізація індексу для ітерації по елементах groups_list
        SET i = 0;

        -- Ітерація по елементах groups_list
        WHILE i < JSON_LENGTH(this_groups_list) DO
            -- Витягуємо та очищуємо значення коду групи
            SET cur_group_code = JSON_UNQUOTE(JSON_EXTRACT(this_groups_list, CONCAT('$[', i, ']')));

            -- Якщо код групи збігається з this_group_code, додаємо нову кількість студентів
            IF cur_group_code = this_group_code THEN
                SET total_students = total_students + new_number_of_students;
            ELSE
                -- Інакше вибираємо кількість студентів для поточної групи з таблиці groups_TB
                SELECT number_of_students INTO this_audience_capacity
                FROM groups_TB
                WHERE group_code = cur_group_code;

                -- Додаємо кількість студентів до загальної кількості
                SET total_students = total_students + this_audience_capacity;
            END IF;

            -- Збільшуємо індекс
            SET i = i + 1;
        END WHILE;

        -- Якщо audience_id не є NULL, вибираємо місткість аудиторії з таблиці audience_TB
        IF audience_id IS NOT NULL THEN
            SELECT number_of_seats INTO audience_capacity
            FROM audience_TB
            WHERE id = audience_id;

            -- Якщо місткість аудиторії не знайдена, встановлюємо результат
            IF audience_capacity IS NULL THEN
                SET result = 'Аудиторія не знайдена для цієї групи.';
            -- Якщо загальна кількість студентів перевищує місткість аудиторії, встановлюємо результат та виходимо з циклу
            ELSEIF total_students > audience_capacity THEN
                SET result = CONCAT('Перевищення на ', total_students - audience_capacity, ' студентів');
                LEAVE read_loop;
            END IF;
        END IF;
    END LOOP;

    -- Закриття курсора
    CLOSE cur;

    -- Якщо результат не був встановлений, встановлюємо його на 'ОК'
    IF result IS NULL THEN
        SET result = 'ОК';
    END IF;
END //

-- Оновлює списки груп в спеціальності
CREATE PROCEDURE update_specialty_codes(
    IN old_code VARCHAR(255),
    IN new_code VARCHAR(255)
)
BEGIN
    DECLARE specialty_id INT;
    DECLARE codes_json JSON;

    -- Отримуємо specialty_id та codes для old_code
    SELECT id, codes INTO specialty_id, codes_json
    FROM specialty_TB
    WHERE JSON_CONTAINS(codes, JSON_QUOTE(old_code));

    -- Якщо old_code знайдено, видаляємо його
    IF specialty_id IS NOT NULL THEN
        IF codes_json IS NULL THEN
            SET codes_json = JSON_ARRAY();
        END IF;

        SET codes_json = JSON_REMOVE(codes_json, JSON_UNQUOTE(JSON_SEARCH(codes_json, 'one', old_code)));

        UPDATE specialty_TB
        SET codes = codes_json
        WHERE id = specialty_id;
    END IF;

    -- Додаємо new_code до codes
    UPDATE specialty_TB
    SET codes = COALESCE(JSON_ARRAY_APPEND(codes, '$', new_code), JSON_ARRAY(new_code))
    WHERE JSON_CONTAINS(codes, JSON_QUOTE(new_code)) = 0 OR codes IS NULL;
END //

DELIMITER ;

-- Процедури для таблиці 'Аудиторія'

DELIMITER //

-- Отримання максимального навантаження на аудиторію
CREATE PROCEDURE get_max_students_in_audience(
    IN this_audience INT,
    OUT max_students INT
)
BEGIN
    DECLARE cur_group_code VARCHAR(255);
    DECLARE this_groups_list JSON;
    DECLARE i INT DEFAULT 0;
    DECLARE done INT DEFAULT 0;
    DECLARE students_count INT;
    DECLARE total_students INT DEFAULT 0;

    -- Оголошення курсора для вибірки записів з таблиці schedule_TB
    DECLARE cur CURSOR FOR
        SELECT groups_list
        FROM schedule_TB
        WHERE audience = this_audience;

    -- Обробник подій для завершення курсора
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Ініціалізація змінної max_students
    SET max_students = 0;

    -- Відкриття курсора
    OPEN cur;

    -- Цикл для обробки даних курсора
    read_loop: LOOP
        -- Вибірка даних з курсора
        FETCH cur INTO this_groups_list;

        -- Якщо курсор завершив вибірку, виходимо з циклу
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Ініціалізація змінної total_students для поточного запису
        SET total_students = 0;

        -- Ініціалізація індексу для ітерації по елементах groups_list
        SET i = 0;

        -- Ітерація по елементах groups_list
        WHILE i < JSON_LENGTH(this_groups_list) DO
            -- Витягуємо та очищуємо значення коду групи
            SET cur_group_code = JSON_UNQUOTE(JSON_EXTRACT(this_groups_list, CONCAT('$[', i, ']')));

            -- Вибираємо кількість студентів для поточної групи з таблиці groups_TB
            SELECT number_of_students INTO students_count
            FROM groups_TB
            WHERE group_code = cur_group_code;

            -- Якщо кількість студентів не є NULL, додаємо її до загальної кількості
            IF students_count IS NOT NULL THEN
                SET total_students = total_students + students_count;
            END IF;

            -- Збільшуємо індекс
            SET i = i + 1;
        END WHILE;

        -- Якщо загальна кількість студентів для поточного запису більша за max_students, оновлюємо max_students
        IF total_students > max_students THEN
            SET max_students = total_students;
        END IF;
    END LOOP;

    -- Закриття курсора
    CLOSE cur;
END //

DELIMITER ;

-- Для сервера

DELIMITER //

-- Для заміни місьцями двох сукупностей пар 
CREATE PROCEDURE UpdateSchedule(
    IN semester ENUM('1','2'),
    IN sourceId VARCHAR(255),
    IN sourceWeek ENUM('1','2'),
    IN sourceDay ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'),
    IN sourcePair ENUM('1','2','3','4','5','6','7'),
    IN destinationId VARCHAR(255),
    IN destinationWeek ENUM('1','2'),
    IN destinationDay ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'),
    IN destinationPair ENUM('1','2','3','4','5','6','7')
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Створення тимчасової таблиці
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_schedule_TB (
        id INT,
        teachers_list JSON,
        groups_list JSON,
        subject_id INT,
        semester_number ENUM('1','2'),
        week_number ENUM('1','2'),
        day_number ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'),
        pair_number ENUM('1','2','3','4','5','6','7'),
        visit_format ENUM('Offline','Online'),
        lesson_type ENUM('Lecture','Practice','Laboratory'),
        audience INT
    );
    
    DELETE FROM temp_schedule_TB;
    
    START TRANSACTION;

    -- Запис джерела в тимчасову таблицю
        INSERT INTO temp_schedule_TB
        SELECT * FROM schedule_TB
        WHERE week_number = sourceWeek AND day_number = sourceDay AND pair_number = sourcePair AND semester_number = semester
        AND JSON_CONTAINS(groups_list, JSON_QUOTE(sourceId), '$');

    -- Запис призначення в тимчасову таблицю
        INSERT INTO temp_schedule_TB
        SELECT * FROM schedule_TB
        WHERE week_number = destinationWeek AND day_number = destinationDay AND pair_number = destinationPair AND semester_number = semester
        AND JSON_CONTAINS(groups_list, JSON_QUOTE(destinationId), '$');

    -- Видалення джерела
        DELETE FROM schedule_TB
        WHERE week_number = sourceWeek AND day_number = sourceDay AND pair_number = sourcePair AND semester_number = semester
        AND JSON_CONTAINS(groups_list, JSON_QUOTE(sourceId), '$');

    -- Видалення призначення
        DELETE FROM schedule_TB
        WHERE week_number = destinationWeek AND day_number = destinationDay AND pair_number = destinationPair AND semester_number = semester
        AND JSON_CONTAINS(groups_list, JSON_QUOTE(destinationId), '$');

    -- Вставка нового джерела, якщо id не NULL
    IF sourceId IS NOT NULL THEN
            INSERT INTO schedule_TB (teachers_list, groups_list, subject_id, semester_number, week_number, day_number, pair_number, visit_format, lesson_type, audience)
            SELECT 
                IF(destinationId IS NULL OR NOT JSON_CONTAINS(teachers_list, JSON_OBJECT('id', CAST(destinationId AS UNSIGNED)), '$'), 
                   teachers_list, 
                   JSON_ARRAY_APPEND(teachers_list, '$', JSON_OBJECT('id', CAST(destinationId AS UNSIGNED)))),
                groups_list,
                subject_id,
                semester,
                destinationWeek,
                destinationDay,
                destinationPair,
                visit_format,
                lesson_type,
                audience
            FROM temp_schedule_TB
            WHERE week_number = sourceWeek AND day_number = sourceDay AND pair_number = sourcePair AND semester_number = semester
            AND JSON_CONTAINS(groups_list, JSON_QUOTE(sourceId), '$');
    END IF;

    -- Вставка нового призначення, якщо id не NULL
    IF destinationId IS NOT NULL THEN
            INSERT INTO schedule_TB (teachers_list, groups_list, subject_id, semester_number, week_number, day_number, pair_number, visit_format, lesson_type, audience)
            SELECT 
                IF(sourceId IS NULL OR NOT JSON_CONTAINS(teachers_list, JSON_OBJECT('id', CAST(sourceId AS UNSIGNED)), '$'), 
                   teachers_list, 
                   JSON_ARRAY_APPEND(teachers_list, '$', JSON_OBJECT('id', CAST(sourceId AS UNSIGNED)))),
                groups_list,
                subject_id,
                semester,
                sourceWeek,
                sourceDay,
                sourcePair,
                visit_format,
                lesson_type,
                audience
            FROM temp_schedule_TB
            WHERE week_number = destinationWeek AND day_number = destinationDay AND pair_number = destinationPair AND semester_number = semester
            AND JSON_CONTAINS(groups_list, JSON_QUOTE(destinationId), '$');
    END IF;

    COMMIT;
END //

-- Підготовка даних для зміни назв груп
CREATE PROCEDURE PrepareTempTable(IN increment BOOL)
BEGIN
    -- Створення тимчасової таблиці, якщо вона не існує
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_groups (
        id INT AUTO_INCREMENT PRIMARY KEY,
        group_code VARCHAR(255),
        number_of_students INT,
        new_group_code VARCHAR(255)
    );

    -- Очищення тимчасової таблиці
    TRUNCATE TABLE temp_groups;

    -- Запис group_code та number_of_students в тимчасову таблицю
    INSERT INTO temp_groups (group_code, number_of_students, new_group_code)
    SELECT 
        group_code, 
        number_of_students,
        CONCAT(
            SUBSTRING(group_code, 1, LOCATE_NUMERIC(group_code) - 1),
            CASE 
                WHEN increment THEN 
                    IF(SUBSTRING(group_code, LOCATE_NUMERIC(group_code), 1) = '9', '0', CHAR(ASCII(SUBSTRING(group_code, LOCATE_NUMERIC(group_code), 1)) + 1))
                ELSE 
                    IF(SUBSTRING(group_code, LOCATE_NUMERIC(group_code), 1) = '0', '9', CHAR(ASCII(SUBSTRING(group_code, LOCATE_NUMERIC(group_code), 1)) - 1))
            END,
            SUBSTRING(group_code, LOCATE_NUMERIC(group_code) + 1)
        ) AS new_group_code
    FROM groups_TB;
END //

-- Заміна даних на тимчасові назви для уникнення дублікатів
CREATE PROCEDURE UpdateToTemp()
BEGIN
    -- Оголошення змінних для курсору
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_group_code VARCHAR(255);
    DECLARE current_id INT;

    -- Оголошення курсору
    DECLARE cur_temp CURSOR FOR
    SELECT id, group_code
    FROM temp_groups
    ORDER BY id;

    -- Оголошення обробника для завершення курсору
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Відкриття курсору для перейменування на тимчасові значення
    OPEN cur_temp;

    -- Початок циклу для обробки кожного запису
    temp_loop: LOOP
        -- Отримання наступного запису
        FETCH cur_temp INTO current_id, current_group_code;

        -- Якщо курсор завершився, виходимо з циклу
        IF done THEN
            LEAVE temp_loop;
        END IF;

        -- Оновлення group_code в groups_TB на тимчасові значення
        UPDATE groups_TB
        SET group_code = CONCAT('temp_', current_id)
        WHERE group_code = current_group_code;
    END LOOP;

    -- Закриття курсору для перейменування на тимчасові значення
    CLOSE cur_temp;
END //

-- Заміна тимчасових даних на нові
CREATE PROCEDURE UpdateToNew()
BEGIN
    -- Оголошення змінних для курсору
    DECLARE done INT DEFAULT FALSE;
    DECLARE new_group_code_from_temp VARCHAR(255);
    DECLARE current_id INT;

    -- Оголошення курсору
    DECLARE cur_new CURSOR FOR
    SELECT id, new_group_code
    FROM temp_groups
    ORDER BY id;

    -- Оголошення обробника для завершення курсору
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Відкриття курсору для перейменування тимчасових значень на нові значення
    OPEN cur_new;

    -- Початок циклу для обробки кожного запису
    new_loop: LOOP
        -- Отримання наступного запису
        FETCH cur_new INTO current_id, new_group_code_from_temp;

        -- Якщо курсор завершився, виходимо з циклу
        IF done THEN
            LEAVE new_loop;
        END IF;

            -- Оновлення group_code в groups_TB на нові значення
            UPDATE groups_TB
            SET group_code = new_group_code_from_temp
            WHERE group_code = CONCAT('temp_', current_id);

    END LOOP;

    -- Закриття курсору для перейменування тимчасових значень на нові значення
    CLOSE cur_new;
END //

delimiter //
-- Оновлення кількості студентів
CREATE PROCEDURE UpdateNumberOfStudents()
BEGIN
    -- Оголошення змінних для курсору
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_group_code VARCHAR(255);
    DECLARE current_number_of_students INT;

    -- Оголошення курсору
    DECLARE cur_update CURSOR FOR
    SELECT group_code, number_of_students
    FROM temp_groups
    ORDER BY id;

    -- Оголошення обробника для завершення курсору
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Оголошення обробника для SQL помилки
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Просто продовжуємо обробку наступних груп
        ROLLBACK;
    END;

    -- Встановлення number_of_students в 0 для всіх груп
    UPDATE groups_TB
    SET number_of_students = 0;

    -- Відкриття курсору для оновлення number_of_students
    OPEN cur_update;

    -- Початок циклу для обробки кожного запису
    update_loop: LOOP
        -- Отримання наступного запису
        FETCH cur_update INTO current_group_code, current_number_of_students;

        -- Якщо курсор завершився, виходимо з циклу
        IF done THEN
            LEAVE update_loop;
        END IF;

        -- Оновлення number_of_students в groups_TB
        UPDATE groups_TB
        SET number_of_students = current_number_of_students
        WHERE group_code = current_group_code;
    END LOOP;

    -- Закриття курсору для оновлення number_of_students
    CLOSE cur_update;
END //

-- Процедура для переходу на наступний/попередній рік
CREATE PROCEDURE UpdateGroups(IN increment BOOL)
BEGIN
    -- Виклик процедур для підготовки тимчасової таблиці та оновлення group_code
    CALL PrepareTempTable(increment);
    CALL UpdateToTemp();
    CALL UpdateToNew();
    CALL UpdateNumberOfStudents();
END //

-- Допоміжна функція для знаходження першого числового символу
CREATE FUNCTION LOCATE_NUMERIC(str VARCHAR(255)) RETURNS INT DETERMINISTIC
LOCATE_NUMERIC: BEGIN 
    DECLARE i INT DEFAULT 1;
    DECLARE len INT DEFAULT LENGTH(str);
    DECLARE ch CHAR(1);
    DECLARE result INT DEFAULT 0;

    WHILE i <= len DO
        SET ch = SUBSTRING(str, i, 1);
        IF ch BETWEEN '0' AND '9' THEN
            SET result = i;
            RETURN result;
        END IF;
        SET i = i + 1;
    END WHILE;

    RETURN result;
END //

DELIMITER ;