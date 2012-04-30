-- Creates a stored procedure for adding databases and users for new websites.
--
-- Author: Daniel Convissor <danielc@analysisandsolutions.com>
-- License: http://www.analysisandsolutions.com/software/license.htm
-- http://github.com/convissor/linode_ubuntu_linux_apache_mysql_php_encrypted_home_directory

DROP PROCEDURE IF EXISTS new_domain;

DELIMITER //

CREATE PROCEDURE new_domain(db_name CHAR(63), admin_user CHAR(16),
	admin_pw CHAR(64), regular_user CHAR(16), regular_pw CHAR(64),
	admin_user_override INT)
BEGIN
	SET @db = db_name;
	SET @db_exists = 0;
	SET @admin = admin_user;
	SET @admin_exists = 0;
	SET @regular = regular_user;
	SET @regular_exists = 0;

	PREPARE stmt FROM "SELECT COUNT(*) INTO @db_exists
		FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?";
	EXECUTE stmt USING @db;

	PREPARE stmt FROM "SELECT COUNT(*) INTO @admin_exists
		FROM user WHERE User = ?";
	EXECUTE stmt USING @admin;

	PREPARE stmt FROM "SELECT COUNT(*) INTO @regular_exists
		FROM user WHERE User = ?";
	EXECUTE stmt USING @regular;

	-- NOTE: strings in the SELECT statements are matched in new-domain.sh.
	-- Changes to these strings need to be synchronized.
	IF (@db_exists > 0) THEN
		SELECT "DATABASE name already taken" AS output;
	ELSEIF (@admin_exists > 0 AND admin_user_override <> 1) THEN
		PREPARE stmt FROM "SELECT
			CONCAT(
				'ADMIN USER name, ',
				@admin,
				', is already taken. ',
				'They have access to the following databases: ',
				GROUP_CONCAT(Db ORDER BY Db SEPARATOR ', ')
			)
			FROM db
			WHERE User = ? AND Select_priv = 'Y'
			GROUP BY User";
		EXECUTE stmt USING @admin;
	ELSEIF (@regular_exists > 0) THEN
		SELECT "REGULAR USER name already taken" AS output;
	ELSE
		SET @sql = CONCAT("CREATE DATABASE ", @db, ";");
		PREPARE stmt FROM @sql; EXECUTE stmt;

		IF (admin_user_override = 0) THEN
			SET @sql = CONCAT("GRANT ALL ON ", db_name, ".* TO ", admin_user, "@localhost IDENTIFIED BY '", admin_pw, "';");
		ELSE
			SET @sql = CONCAT("GRANT ALL ON ", db_name, ".* TO ", admin_user, "@localhost;");
		END IF;

		PREPARE stmt FROM @sql; EXECUTE stmt;

		SET @sql = CONCAT("GRANT SELECT, INSERT, UPDATE, DELETE ON ", db_name, ".* TO ", regular_user, "@localhost IDENTIFIED BY '", regular_pw, "';");
		PREPARE stmt FROM @sql; EXECUTE stmt;

		FLUSH PRIVILEGES;
	END IF;

	DEALLOCATE PREPARE stmt;
END
//

DELIMITER ;
