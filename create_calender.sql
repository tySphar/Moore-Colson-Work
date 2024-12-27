CREATE PROCEDURE dbo.CreateCalendar
    @startDate DATE = '2019-01-01',
    @endDate DATE = NULL  -- Default to NULL, we'll set it to 5 years from current date if not provided
AS
BEGIN
    SET NOCOUNT ON;

    -- If end date is not provided, set it to 5 years from the current date
    IF @endDate IS NULL
    BEGIN
        SET @endDate = DATEADD(YY, 5, DATEFROMPARTS(YEAR(GETDATE()), 12, 31));
    END

    -- Drop temp table if exists
    IF OBJECT_ID('tempdb..#calendarTbl') IS NOT NULL 
        DROP TABLE #calendarTbl;

    -- Create the calendar table
    CREATE TABLE #calendarTbl (
        fullDate DATE PRIMARY KEY,
        dowName NVARCHAR(10),      -- Day of week name
        dowNum INT,                -- Day of week number
        isBusDay INT,              -- 1 = Business day, 0 = Non-business day
        holiday INT                -- 1 = Holiday, 0 = Not a holiday
    );

    -- Generate the calendar
    WHILE @startDate <= @endDate
    BEGIN
        INSERT INTO #calendarTbl
        SELECT 
            @startDate, 
            DATENAME(WEEKDAY, @startDate),  -- Day of the week name
            DATEPART(WEEKDAY, @startDate),  -- Day of the week number (1 = Sunday, 7 = Saturday)
            CASE
                WHEN DATEPART(WEEKDAY, @startDate) IN (1, 7) THEN 0  -- Sunday (1) and Saturday (7) are non-business days
                ELSE 1  -- Other days are business days
            END,
            0  -- Default holiday flag (0 = Not a holiday)
        
        SET @startDate = DATEADD(DD, 1, @startDate);  -- Move to next day
    END;

    -- Static holidays (Christmas, New Year, etc.)
    DECLARE @staticHolidays TABLE (
        holidayMonth INT,
        holidayDay INT
    );

    INSERT INTO @staticHolidays
    VALUES 
        (12, 25),  -- Christmas
        (1, 1),    -- New Year's Day
        (7, 4),    -- Independence Day
        (11, 11);  -- Veteran's Day

    -- Mark static holidays (e.g., Christmas, New Year's Day) as non-business days
    WITH firstHolidays AS (
        SELECT cal.*
        FROM #calendarTbl cal
        WHERE EXISTS (
            SELECT *
            FROM @staticHolidays sth
            WHERE MONTH(cal.fullDate) = sth.holidayMonth
              AND DAY(cal.fullDate) = sth.holidayDay
        )
    )
    UPDATE cal
    SET
        cal.isBusDay = 0,
        cal.holiday = 1
    FROM #calendarTbl cal
    INNER JOIN firstHolidays fhl ON fhl.fullDate = cal.fullDate;

    -- Variable holidays (e.g., MLK Day, Memorial Day, Labor Day)
    DECLARE @variableHolidays TABLE (
        varMo INT,
        varDow INT,
        varWhichOne INT
    );

    -- Insert variable holidays: month, day of week (1 = Sunday, 7 = Saturday), and the occurrence (1 = 1st, 2 = 2nd, etc.)
    INSERT INTO @variableHolidays
    VALUES 
        (1, 2, 3),   -- Martin Luther King Jr. Day (3rd Monday of January)
        (2, 2, 3),   -- Presidents' Day (3rd Monday of February)
        (5, 1, 99),  -- Memorial Day (Last Monday of May)
        (9, 1, 01),  -- Labor Day (1st Monday of September)
        (11, 5, 04); -- Thanksgiving (4th Thursday of November)

    -- Step 1: Prepare for identifying the variable holidays
    WITH secondHolidaysPrep AS (
        SELECT cal.*,
            ROW_NUMBER() OVER (PARTITION BY MONTH(cal.fullDate), YEAR(cal.fullDate), cal.dowNum ORDER BY cal.fullDate) AS dowRnAsc,
            ROW_NUMBER() OVER (PARTITION BY MONTH(cal.fullDate), YEAR(cal.fullDate), cal.dowNum ORDER BY cal.fullDate DESC) + 98 AS dowRnDesc
        FROM #calendarTbl cal
    )

    -- Step 2: Identify variable holidays based on occurrence and day of the week
    , secondHolidays AS (
        SELECT shp.*
        FROM secondHolidaysPrep shp
        WHERE EXISTS (
            SELECT *
            FROM @variableHolidays vhl
            WHERE MONTH(shp.fullDate) = vhl.varMo
              AND shp.dowNum = vhl.varDow
              AND (shp.dowRnAsc = vhl.varWhichOne OR shp.dowRnDesc = vhl.varWhichOne)
        )
    )

    -- Step 3: Mark the identified variable holidays as non-business days
    UPDATE cal
    SET
        cal.isBusDay = 0,
        cal.holiday = 1
    FROM #calendarTbl cal
    INNER JOIN secondHolidays shl ON shl.fullDate = cal.fullDate;

    -- Return the calendar table with holidays and business days marked
    SELECT * FROM #calendarTbl ORDER BY fullDate;

    -- Drop the temp table after the process is completed
    DROP TABLE #calendarTbl;
END;
GO
