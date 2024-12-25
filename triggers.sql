-- Тригери для таблиці 'Навчальний план'

DELIMITER //

CREATE TRIGGER before_curriculum_insert
BEFORE INSERT ON curriculum_TB
FOR EACH ROW
BEGIN	
	declare status VARCHAR(255);
    declare new_correspondence bool;
    --  Видаляємо дублікати
    call removing_duplicates_curriculum(new.related_groups, new.related_teachers);
    
    -- Перевіряємо чи всі групи та вчителі є в відповідних таблицях
	call check_gr_th_existence(new.related_groups, new.related_teachers, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
        
    -- Перевіряємо відповідність запланованих пар та пар в розкладі      
    call check_correspondence(new.related_groups, new.related_teachers, new_correspondence);
    SET new.correspondence = new_correspondence;
        
END //

CREATE TRIGGER before_curriculum_update
BEFORE UPDATE ON curriculum_TB
FOR EACH ROW
BEGIN
	declare status VARCHAR(255);
    declare new_correspondence bool;
    -- Використовуємо глобальну змінну щоб вимкнути тригер при зміні таблиць груп та вчителя
    IF @disable_trigger IS NULL THEN
		--  Видаляємо дублікати
		call removing_duplicates_curriculum(new.related_groups, new.related_teachers);
		-- Перевіряємо чи не видаляємо ми групи чи вчителів які є в розкладі
		call check_schedule_existence(old.id, old.related_groups, old.related_teachers, new.related_groups, new.related_teachers, status);
		IF status != 'ОК' THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
		END IF;
		
		-- Перевіряємо чи всі групи та вчителі є в відповідних таблицях
		call check_gr_th_existence(new.related_groups, new.related_teachers, status);
		IF status != 'ОК' THEN
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
		END IF;
			
		-- Перевіряємо відповідність запланованих пар та пар в розкладі     
		call check_correspondence(new.related_groups, new.related_teachers, new_correspondence);
		SET new.correspondence = new_correspondence;
        
	END IF;
END //

CREATE TRIGGER before_curriculum_delete
BEFORE DELETE ON curriculum_TB
FOR EACH ROW
BEGIN
	declare status VARCHAR(255);
    -- Перевіряємо чи не видаляємо ми групи чи вчителів які є в розкладі
	call check_schedule_existence(old.id, old.related_groups, old.related_teachers, null, null, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
END //

DELIMITER ;

-- Тригери для таблиці 'Розклад'
DELIMITER //

CREATE TRIGGER before_schedule_insert
BEFORE INSERT ON schedule_TB
FOR EACH ROW
BEGIN	
    DECLARE status VARCHAR(255);
    
    -- Видаляємо дублікати
    CALL removing_duplicates_schedule_TB(NEW.groups_list, NEW.teachers_list);
    
    -- Перевіряємо чи є групи та вчителя в плані
    CALL check_in_curriculum(NEW.groups_list, NEW.teachers_list, NEW.subject_id, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевіряємо конфлікт розкладів
    CALL check_schedule_conflict(NEW.subject_id, FALSE, NEW.groups_list, NEW.teachers_list, NEW.semester_number, NEW.week_number, NEW.day_number, NEW.pair_number, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевірка на те що загальна сума студентів не перевищує вмістимість аудиторії
    CALL check_audience_capacity(NEW.audience, NEW.groups_list, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевірка на конфлікт для аудиторії
    SELECT COUNT(*) INTO @audience_conflict
    FROM schedule_TB
    WHERE audience = NEW.audience
    AND semester_number = NEW.semester_number
    AND week_number = NEW.week_number
    AND day_number = NEW.day_number
    AND pair_number = NEW.pair_number;

    IF @audience_conflict > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Конфлікт для аудиторії: Аудиторія вже зайнята в цей час.';
    END IF;

    -- Оновлює розплановані пари в розкладі
    CALL update_scheduled_lessons(NEW.groups_list, NEW.teachers_list, NEW.lesson_type, NEW.subject_id, TRUE);
END //

CREATE TRIGGER before_schedule_update
BEFORE UPDATE ON schedule_TB
FOR EACH ROW
BEGIN
    DECLARE status VARCHAR(255);
    
    -- Видаляємо дублікати
    CALL removing_duplicates_schedule_TB(NEW.groups_list, NEW.teachers_list);
    
    -- Перевіряємо чи є групи та вчителя в плані
    CALL check_in_curriculum(NEW.groups_list, NEW.teachers_list, NEW.subject_id, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевіряємо конфлікт розкладів
    CALL check_schedule_conflict(OLD.subject_id, TRUE, NEW.groups_list, NEW.teachers_list, NEW.semester_number, NEW.week_number, NEW.day_number, NEW.pair_number, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевірка на те що загальна сума студентів не перевищує вмістимість аудиторії
    CALL check_audience_capacity(NEW.audience, NEW.groups_list, status);
    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    
    -- Перевірка на конфлікт для аудиторії (якщо аудиторія змінюється)
    IF OLD.audience != NEW.audience THEN
        SELECT COUNT(*) INTO @audience_conflict
        FROM schedule_TB
        WHERE audience = NEW.audience
        AND semester_number = NEW.semester_number
        AND week_number = NEW.week_number
        AND day_number = NEW.day_number
        AND pair_number = NEW.pair_number
        AND id != NEW.id; -- Виключаємо поточну пару

        IF @audience_conflict > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Конфлікт для аудиторії: Аудиторія вже зайнята в цей час.';
        END IF;
    END IF;
    
    -- Оновлює розплановані пари в розкладі
    CALL update_scheduled_lessons(OLD.groups_list, OLD.teachers_list, OLD.lesson_type, OLD.subject_id, FALSE);    
    CALL update_scheduled_lessons(NEW.groups_list, NEW.teachers_list, NEW.lesson_type, NEW.subject_id, TRUE);
END //

DELIMITER ;

-- Тригери для таблиці 'Вчителі'

DELIMITER //

CREATE TRIGGER before_update_teacher
BEFORE UPDATE ON teachers_TB
FOR EACH ROW
BEGIN
	-- Оновлюємо ID та Ім'я в плані та розкладі
	CALL update_teacher(old.id, NEW.id, NEW.full_name);
END //

CREATE TRIGGER before_delete_teacher
BEFORE DELETE ON teachers_TB
FOR EACH ROW
BEGIN
    DECLARE status VARCHAR(255);

    -- Перевірка, чи є вчитель в навчальному плані
    CALL check_teacher_in_curriculum(OLD.id, status);

    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
END //

DELIMITER ;

-- Тригери для таблиці 'Групи'

DELIMITER //

CREATE TRIGGER after_insert_groups_TB
AFTER INSERT ON groups_TB
FOR EACH ROW
BEGIN
	-- Додаємо код групи в таблицю спеціальностей
    CALL update_specialty_codes(null, NEW.group_code);
END //

CREATE TRIGGER before_update_group
BEFORE UPDATE ON groups_TB
FOR EACH ROW
BEGIN
	DECLARE status VARCHAR(255);
    -- Якщо нова кількість студентів
    IF NEW.number_of_students != OLD.number_of_students THEN
		-- Перевіряємо вмістимість аудиторій
        CALL check_group_capacity(NEW.group_code, NEW.number_of_students, status);
		
        IF status != 'ОК' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
        END IF;
    END IF;

    -- Оновлюємо код групи в плані, розкладі та таблиці спеціальності
    IF OLD.group_code <> NEW.group_code THEN
		CALL update_group(OLD.group_code, NEW.group_code);
        CALL update_specialty_codes(OLD.group_code, NEW.group_code);
    END IF;
END //

CREATE TRIGGER before_delete_group
BEFORE DELETE ON groups_TB
FOR EACH ROW
BEGIN
    DECLARE status VARCHAR(255);

    -- Перевірка, чи є група в навчальному плані
    CALL check_group_in_curriculum(OLD.group_code, status);

    IF status != 'ОК' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
    END IF;
    -- Видаляємо код групи в таблиці спеціальності
    CALL update_specialty_codes(OLD.group_code, NULL);
END //

DELIMITER ;

-- Тригери для таблиці 'Аудиторія'

DELIMITER //

CREATE TRIGGER before_update_audience
BEFORE UPDATE ON audience_TB
FOR EACH ROW
BEGIN
    DECLARE max_students INT;
    DECLARE status VARCHAR(255);
    DECLARE audience_exists INT DEFAULT 0;
	
    
    SELECT COUNT(*) INTO audience_exists
    FROM schedule_TB
    WHERE audience = OLD.id;
	-- Якщо аудиторія використовується в розкладі та кількість місць змінилося
    IF audience_exists and NEW.number_of_seats != OLD.number_of_seats  THEN
		-- Отримуємо максимальне навантаження на аудиторію 
		CALL get_max_students_in_audience(OLD.id, max_students);
        -- Перевіряємо чи нове число місць більше за максимальне навантаження
		IF max_students > NEW.number_of_seats THEN
			set status = CONCAT('Перевищення на ', max_students - NEW.number_of_seats, ' студентів');
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = status;
		END IF;
    END IF;
END //

DELIMITER ;

-- тригери для шифрування(шифрує пароль щоб передавати його до серверу, наразі використовує хешування, в майбутньому буде замінено на більш захищений)

DELIMITER //

CREATE TRIGGER before_insert_admin_list
BEFORE INSERT ON admin_list_TB
FOR EACH ROW
BEGIN
    SET NEW.password_hash = SHA2(NEW.password, 256);
END //

CREATE TRIGGER before_update_admin_list
BEFORE UPDATE ON admin_list_TB
FOR EACH ROW
BEGIN
    SET NEW.password_hash = SHA2(NEW.password, 256);
END //

DELIMITER ;