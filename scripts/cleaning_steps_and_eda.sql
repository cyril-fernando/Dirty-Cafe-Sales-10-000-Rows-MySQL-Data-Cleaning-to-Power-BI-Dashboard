-- JUNE 1 2025
-- Creation of schema, and exporting the csv file of dirty cafe sales
-- I just used the tool above "create a new schema"
-- I set the dirty_cafe_sales as the default so querying is much easier
-- importing the csv through import wizard, named the table 'cafe_sales', and made every column text data type (to avoid complications) 
-- 10k rows imported

SELECT * 
FROM cafe_sales;

-- changing the column names to standard naming 
ALTER TABLE cafe_sales
CHANGE COLUMN 	`ï»¿Transaction ID` `transaction_id` TEXT,
CHANGE COLUMN 	`Item` `item` TEXT,
CHANGE COLUMN    `Quantity` `quantity` TEXT,
CHANGE COLUMN    `Price Per Unit` `price_per_unit` TEXT,
CHANGE COLUMN    `Total Spent` `total_spent` TEXT,
CHANGE COLUMN    `Payment Method` `payment_method` TEXT,
CHANGE COLUMN    `Location` `location` TEXT,
CHANGE COLUMN    `Transaction Date` `transaction_date` TEXT;

-- creating a staging table for data cleaning, validation, etc.
CREATE TABLE staging_cafe_sales
LIKE cafe_sales;

-- inserting data from the raw to here
INSERT INTO staging_cafe_sales
SELECT * 
FROM cafe_sales;

SELECT * 
FROM staging_cafe_sales;

-- trimming the whitespaces to each column
UPDATE staging_cafe_sales
SET 
	transaction_id = TRIM(transaction_id),
	item = TRIM(item),
    quantity = TRIM(quantity),
    price_per_unit = TRIM(price_per_unit),
    total_spent = TRIM(total_spent),
    payment_method = TRIM(payment_method),
    location = TRIM(location),
    transaction_date = TRIM(transaction_date);
    
-- checking duplicates
SELECT transaction_id, COUNT(*) AS count
FROM staging_cafe_sales
GROUP BY transaction_id
HAVING COUNT > 1; -- NO DUPLICATES?

SELECT LOWER(item), quantity, price_per_unit, total_spent, LOWER(payment_method), LOWER(location), transaction_date, COUNT(*) AS count
FROM staging_cafe_sales
GROUP BY LOWER(item), quantity, price_per_unit, total_spent, LOWER(payment_method), LOWER(location), transaction_date
HAVING COUNT > 1
ORDER BY 1; -- GOT 138 ROWS SO THERE ARE DUPLICATES (TWO'S AND THREE'S COPIES)? OR IS THERE? MAYBE THEY'RE JUST THE SAME ORDERS, BUT DIFFERENT PEOPLE

-- FURTHER INVESTIGATING
SELECT *, ROW_NUMBER() 
	OVER(PARTITION BY LOWER(item), quantity, price_per_unit, total_spent, LOWER(payment_method), LOWER(location), transaction_date) AS row_num
FROM staging_cafe_sales;

WITH duplicate_cte AS
(
SELECT *, ROW_NUMBER() 
	OVER(PARTITION BY LOWER(item), quantity, price_per_unit, total_spent, LOWER(payment_method), LOWER(location), transaction_date) AS row_num
FROM staging_cafe_sales
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;

-- JUNE 2, 2025
SELECT * 
FROM staging_cafe_sales
WHERE transaction_id = 'TXN_7063005' OR transaction_id = 'TXN_5239202'; -- NO DUPLICATES, I JUST CIRCLED THROUGH QUERIES 

-- CHECKING DISTINCT VALUES FOR EACH COLUMN
SELECT * 
FROM staging_cafe_sales;

SELECT DISTINCT(item), quantity, price_per_unit, total_spent, transaction_id
FROM staging_cafe_sales
ORDER BY 1; -- A LOT OF MISSING VALUES BUT CAN FILLED (IMPUTE)

SELECT DISTINCT(payment_method), location, transaction_date, transaction_id
FROM staging_cafe_sales
ORDER BY 1; -- LOTS OF MISSING AND ERRORS, I MIGHT JUST FILL WITH UNKNOWN WITH THESE COLUMNS DEPENDING IF THEY REALLY BOUGHT ITEMS

-- I WILL FOCUS FIRST ON FIXING THE item, quantity, price_per_unit, and total_spent COLUMNS AS THEY ARE CRUCIAL IN EDA
-- I WILL LIST DOWN THE CORRESPONDING VALUES FOR EACH ITEM 
-- '', Cake:3, Coffee:2, Cookie:1, ERROR:, Juice:3, Salad:5, Sandwich:4, Smoothie:4, Tea:1.5, UNKNOWN:
-- ANALYSIS: IM THINKING OF USING IF STATEMENTS TO FILL OUT THE ITEMS, BUT THERE ARE SIMILAR VALUES LIKE CAKE AND JUICE WITH PRICE OF 3 SO IDK

-- CASE STATEMENT TESTING
SELECT item,
	CASE 
		WHEN 
			LOWER(item) = 'error' OR LOWER(item) = 'UNKNOWN' OR item = '' THEN NULL
			ELSE item
		END AS new_item,
    quantity, 
    CASE 
		WHEN
			LOWER(quantity) = 'error' OR LOWER(quantity) = 'UNKNOWN' OR quantity = '' THEN NULL
			ELSE quantity
		END AS new_quanity
FROM staging_cafe_sales
ORDER BY 1; -- GOOD, NOW SEARCHING OF OTHER WAYS TO DO THIS TO OTHER COLUMNS INSTEAD OF COPY PASTING IF STATEMENTS 

-- FOUND A POTENTIAL SOLUTION, IT'S ABOUT CREATING MY OWN FUNCTIONS
DELIMITER $$

CREATE FUNCTION clean(input_value TEXT) 
RETURNS TEXT 
DETERMINISTIC 
BEGIN 
  RETURN CASE
    WHEN LOWER(input_value) IN ('', 'error', 'unknown') THEN NULL
    ELSE input_value
  END;
END$$
-- restore default delimiter for future queries
DELIMITER ;
-- ABOVE IS WHAT I LEARNED FROM GPT ABOUT FUNCTIONS, MY NOTES FROM MY OWN UNDERSTANDING
SELECT 
	transaction_id
    item, clean(item),
    quantity, clean(quantity),
    price_per_unit, clean(price_per_unit),
    total_spent, clean(total_spent),
    payment_method, clean(payment_method),
    location, clean(location),
    transaction_date, clean(transaction_date)
FROM staging_cafe_sales
WHERE 
	clean(item) IS NULL OR clean(quantity) IS NULL OR 
	clean(price_per_unit) IS NULL OR clean(total_spent) IS NULL OR 
	clean(payment_method) IS NULL OR clean(location) IS NULL OR clean(transaction_date) IS NULL
ORDER BY 1; -- THIS LOOKS REPETITIVE AND UGLY, MAYBE ILL LOOK FOR OTHER METHODS. AS I WAS THINKING IN THE FUTURE WHAT IF IM HANDLING 20 COLUMNS BUT IT WORKED
-- TOTAL OF 6911 ROWS OF MISSING, UNKNOWN, ERROR VALUES

SELECT *
FROM staging_cafe_sales
ORDER BY location;

-- UPDATING ALL THE MISSING VALUES
START TRANSACTION;
UPDATE staging_cafe_sales
	SET
		item = clean(item), 
		quantity = clean(quantity), 
		price_per_unit = clean(price_per_unit), 
		total_spent = clean(total_spent),
		payment_method = clean(payment_method), 
		location = clean(location), 
		transaction_date = clean(transaction_date);
SELECT * FROM staging_cafe_sales;
ROLLBACK;
-- WELL THAT DIDNT WORK, AUTOCOMMIT WAS ON YIKES. THOUGH EVERYTHING WORKED PERFECTLY GOTTA BE CAREFUL NEXT TIME. 6911 ROWS CLEANED


SELECT *
FROM staging_cafe_sales
WHERE item IS NULL AND quantity IS NULL AND price_per_unit IS NULL;
-- I THOUGHT OF DELETING THESE BUT TOTAL SPENT COLUMN IS GOOD FOR THE OVERALL REVENUE SO RETAIN
-- TESTING IMPLEMENTATION OF UNKNOWNS 

/* START TRANSACTION;
UPDATE staging_cafe_sales
	SET payment_method = CASE WHEN payment_method IS NULL THEN 'Unknown' ELSE payment_method END, 
		location = CASE WHEN location IS NULL THEN 'Unknown' ELSE location END,
        transaction_date = CASE WHEN transaction_date IS NULL THEN 'Unknown' ELSE transaction_date END;
ROLLBACK; */
-- 6025 ROWS CHANGED, I SHALL PROCEED WITH COMMIT

SELECT * 
FROM staging_cafe_sales
WHERE item = 'Coffee' OR price_per_unit = 2 
ORDER BY item;

-- SO PROBLEM, I CAN'T JUST IMPUTE BASED ON THE PRICE PER UNIT OR ITEM AS THERE ARE DUPLICATES
-- I'LL DO FIRST THE ONES THAT HAS NO DUPLICATES

/*START TRANSACTION;
UPDATE staging_cafe_sales
	SET item = 
		CASE WHEN item = 'Coffee' AND price_per_unit IS NULL THEN price_per_unit = 2
			 WHEN price_per_unit = 2 AND item IS NULL THEN item = 'Coffee'
             WHEN item IS NULL AND price_per_unit = 2 THEN item = 'Coffee'
             WHEN price_per_unit IS NULL AND item = 'Coffee' THEN price_per_unit = 2
		END;
	ROLLBACK; THINKING OF BETTER WAY TO DO THIS */
    
-- GO AGAIN TOMORROW 
-- June 3 2025

WITH price_map AS
(
SELECT item, MIN(price_per_unit) AS price, COUNT(*) OVER() 
FROM staging_cafe_sales
WHERE
	item IS NOT NULL AND price_per_unit IS NOT NULL
GROUP BY item
HAVING COUNT(DISTINCT price_per_unit) = 1
),
unique_items AS
(
SELECT price
FROM price_map
GROUP BY price
HAVING COUNT(*) = 1
) -- FIRST CTE SHOWED ITEMS THAT EXACTLY HAVE ONE CORRESPONDING PRICE, CHECKING IF THERE ARE OTHER PRICES PER ITEM. SECOND ONE SHOWED ITEMS WITH NO DUPLICATES IN PRICES
SELECT *
FROM unique_items
ORDER BY 1; -- THIS IS A GPT QUERY ILL FIND ANOTHER WAY DOWN THE ROAD SOMETHING I CAN UNDERSTAND MORE AND WRiTE

SELECT transaction_id, COUNT(*)
FROM staging_cafe_sales
GROUP BY transaction_id
HAVING COUNT(*) > 1; -- PROBLEM ARISED, I MADE THE STAGING TABLE 20K ROWS INSTEAD OF 10K SO I DUPLICATED IT. I THINK BECAUSE I DID SOMETHING WITH START TRANSACTION WITH THE TWO CTE'S

-- FIXING IT 
-- JUNE 3 AND 4 FOCUS ON THESE
CREATE TABLE backup_table1 AS
SELECT * FROM staging_cafe_sales; -- CREATED A BACKUP AS I MIGHT BROKE IT AGAIN

SELECT DISTINCT transaction_id
FROM staging_cafe_sales; -- LOOKING FOR DISTINCT VALUES, HAS 10K SO IT JUST DUPLICATED

SELECT * 
FROM staging_cafe_sales
ORDER BY 1; -- 20K
-- so what just happened is it just inserted the values from the cafe_sales
-- all i need to do is remove the '', UKNOWN, and ERROR from columns and remove those rows 


DELETE
FROM staging_cafe_sales
WHERE 
  BINARY payment_method IN ('ERROR', '', 'UNKNOWN') 
  OR BINARY location IN ('ERROR', '', 'UNKNOWN') 
  OR BINARY transaction_date IN ('ERROR', '', 'UNKNOWN')
  OR BINARY item IN ('ERROR', '', 'UNKNOWN')
  OR BINARY quantity IN ('ERROR', '', 'UNKNOWN')
  OR BINARY price_per_unit IN ('ERROR', '', 'UNKNOWN')
  OR BINARY total_spent IN ('ERROR', '', 'UNKNOWN'); -- IT SAYS BINARY DEPRECATED AND JUST USE CAST, THO IT WORKED. 6911 ROWS 
-- used the binary keyword as gpt said it's to be case sensitive
-- WILL CHANGE THE SELECT TO DELETE TO REMOVE THE 6911 FRAUD ROWS
-- SO AT THIS POINT I STILL HAVE 13089 ROWS
-- and when i ran this below it has 3089, so thats the number of duplicates left i believe 	

SELECT transaction_id, COUNT(*) 
FROM staging_cafe_sales
GROUP BY transaction_id
HAVING COUNT(*) >1;

SELECT 
  transaction_id,
  item,
  quantity,
  price_per_unit,
  total_spent,
  payment_method,
  location,
  transaction_date, COUNT(*)
FROM staging_cafe_sales
GROUP BY transaction_id, item,
  quantity,
  price_per_unit,
  total_spent,
  payment_method,
  location,
  transaction_date
HAVING COUNT(*) > 1
ORDER BY 1; -- SO WHAT THIS DOES IS JUST SHOWS THE WHOLE TABLE AND COUNT OF THE RECORDED EXACT VALUES, 3089 ROWS

-- SO i found a solution and it's about adding a surrogate key with the use of cte then deleting it. ill try to understand line by line
-- so this query below just adds the column of surrogate key id with bigint data type to handle large numbers, not null makes sure that every row must have a value
-- autoincrement just increments to the next int, primary key makes the id a unique identifier
-- and first placed this column at the first column list
ALTER TABLE staging_cafe_sales
ADD COLUMN id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;

SELECT * FROM staging_cafe_sales;

-- cte making 
WITH temp_table AS (
					SELECT id, ROW_NUMBER() OVER( 
						PARTITION BY transaction_id, item, quantity, price_per_unit, total_spent, payment_method, location, transaction_date ORDER BY id) AS rn
					FROM staging_cafe_sales
) 
-- so the cte table basically just selects the id, add a row number to each partitioned group columns ordered by id
-- so it gives the id with duplicates, it says what id has two copies
DELETE
FROM staging_cafe_sales
WHERE id IN (SELECT id FROM temp_table WHERE rn > 1); -- 3089 rows returned 
-- and this query above is selecting all the rows that has two copies which are the duplicates
-- now delete them so ill just switch select with delete

SELECT * FROM staging_cafe_sales; -- 10k rows is back, now on to filling items again
ALTER TABLE staging_cafe_sales
DROP COLUMN id;

SELECT * 
FROM staging_cafe_sales
WHERE item IS NULL OR quantity IS NULL OR price_per_unit IS NULL or total_spent IS NULL
ORDER BY 1; -- 2268 ROWS HAVE NULLS on columns item, quantity, price per unit , and total_spent

-- figuring out how many items share the same price
SELECT item, COUNT(DISTINCT price_per_unit), GROUP_CONCAT(DISTINCT price_per_unit ORDER BY 1 SEPARATOR ', ')
    FROM staging_cafe_sales
    WHERE item IS NOT NULL AND price_per_unit IS NOT NULL
    GROUP BY item;

 SELECT price_per_unit, COUNT(DISTINCT item) count, GROUP_CONCAT(DISTINCT item ORDER BY item SEPARATOR ', ') items
 FROM staging_cafe_sales
 WHERE item IS NOT NULL AND price_per_unit IS NOT NULL
 GROUP BY price_per_unit;
 -- SO cake and juice share 3, likely sandwich and smoothie share 4. I'll just take in the items that has no share values and then fill the nulls
 
 
	/*WITH u_table AS (
				 SELECT price_per_unit, COUNT(DISTINCT item) cn
				 FROM staging_cafe_sales
				 WHERE item IS NOT NULL AND price_per_unit IS NOT NULL
				 GROUP BY price_per_unit
				 HAVING cn = 1)
	 SELECT DISTINCT s.item, s.price_per_unit
	 FROM staging_cafe_sales s 
	 INNER join u_table u 
	 ON s.price_per_unit = u.price_per_unit
	 WHERE s.item IS NOT NULL AND s.price_per_unit IS NOT NULL
	 ORDER BY 1; */ -- this could work but gpt suggested to just make another reference table, i think it's much more simple and easy to remember
     
-- JUNE 15 2025, 
-- will make a reference table
CREATE TEMPORARY TABLE ref_table 
(item VARCHAR(50) PRIMARY KEY,
 price_per_unit DECIMAL(10, 1));
 
INSERT INTO ref_table VALUES 
	('Coffee',   2),
	('Cookie',   1),
	('Salad',    5),
	('Tea',      1.5);
    
-- creating index
CREATE INDEX idx ON ref_table(price_per_unit);

SELECT * FROM ref_table;

SELECT * FROM staging_cafe_sales s
INNER JOIN ref_table t
ON s.item = t.item
WHERE s.price_per_unit IS NULL AND s.item is NOT NULL;

SELECT * FROM staging_cafe_sales s
INNER JOIN ref_table t
ON s.price_per_unit = t.price_per_unit
WHERE s.item IS NULL AND s.price_per_unit is NOT NULL;

START TRANSACTION;
UPDATE staging_cafe_sales s
INNER JOIN ref_table t
ON s.item = t.item
SET s.price_per_unit = t.price_per_unit
WHERE s.price_per_unit IS NULL AND s.item IS NOT NULL;

UPDATE staging_cafe_sales s
INNER JOIN ref_table t
ON s.price_per_unit = t.price_per_unit
SET s.item = t.item
WHERE s.item IS NULL AND s.price_per_unit IS NOT NULL;

UPDATE staging_cafe_sales
SET total_spent = quantity*price_per_unit
WHERE total_spent IS NULL AND (price_per_unit IS NOT NULL AND quantity IS NOT NULL);

UPDATE staging_cafe_sales
SET quantity = total_spent/price_per_unit
WHERE quantity IS NULL AND (total_spent IS NOT NULL AND price_per_unit IS NOT NULL);

UPDATE staging_cafe_sales
SET price_per_unit = total_spent/quantity
WHERE price_per_unit IS NULL AND (total_spent IS NOT NULL AND quantity IS NOT NULL);

UPDATE staging_cafe_sales
SET item = 'Tea'
WHERE (item IS NULL and price_per_unit = 1.5);

UPDATE staging_cafe_sales
SET item = 'Cookie'
WHERE (item IS NULL and price_per_unit = 1);

UPDATE staging_cafe_sales
SET item = CASE
			WHEN price_per_unit = 2 THEN 'Coffee'
			ELSE 'Salad'
		END
WHERE item IS NULL AND price_per_unit NOT IN (3,4);

SELECT * FROM staging_cafe_sales;
ROLLBACK;
-- will alter the columns later for consistent data formatting

SELECT *
FROM staging_cafe_sales
WHERE total_spent IS NULL AND (price_per_unit IS NOT NULL AND quantity IS NOT NULL)
ORDER BY 5; -- WILL BE PUT INTO START TRANSACTION TO UPDATE

SELECT * FROM staging_cafe_sales
WHERE quantity IS NULL AND (total_spent IS NOT NULL AND price_per_unit IS NOT NULL)
ORDER BY 5; -- SENT TO UPDATE

SELECT * FROM staging_cafe_sales
WHERE price_per_unit IS NULL AND (total_spent IS NOT NULL AND quantity IS NOT NULL)
ORDER BY 5; -- SENT TO UPDATE

SELECT * FROM staging_cafe_sales
WHERE price_per_unit IS NULL OR total_spent IS NULL or quantity IS NULL;

SELECT *
FROM staging_cafe_sales
WHERE (item IS NULL and price_per_unit = 1.5); -- just looking to impute possibilities

SELECT *
FROM staging_cafe_sales
WHERE (item IS NULL and price_per_unit = 1); -- IDK WHY THE MERGE INITIALLY DIDNT FULLY WORK SO SOME ITEMS THAT HAS PRICE DIDNT UPDATE

SELECT *
FROM staging_cafe_sales
WHERE item IS NULL AND price_per_unit NOT IN (3,4); -- 9 rows will fix quickly

SELECT *
FROM staging_cafe_sales
WHERE quantity IS NULL AND total_spent IS NOT NULL AND item IS NOT NULL; -- 6 ROWS

UPDATE staging_cafe_sales
SET price_per_unit = CASE
					 WHEN item = 'Cake' THEN 3
                     WHEN item IN ('Sandwich', 'Smoothie') THEN  4
					END
WHERE quantity IS NULL AND total_spent IS NOT NULL AND item IS NOT NULL;

UPDATE staging_cafe_sales
SET quantity = total_spent/price_per_unit
WHERE quantity IS NULL AND total_spent IS NOT NULL AND item IS NOT NULL;


SELECT *
FROM staging_cafe_sales
ORDER BY 2;
-- TABLE IS CLEANED, WILL NOW PROCEED TO EDA AFTER ALTERING TABLE DATA TYPES OR SHOULD I?

ALTER TABLE staging_cafe_sales
MODIFY COLUMN price_per_unit FLOAT;

SELECT * FROM staging_cafe_sales
WHERE CAST(price_per_unit AS CHAR) LIKE '%.00'; -- NO ROWS, GOOD

DESCRIBE staging_cafe_sales;

SELECT *
FROM staging_cafe_sales
WHERE (item IS NULL AND total_spent IS NULL);

ALTER TABLE staging_cafe_sales
MODIFY transaction_id VARCHAR(20),
MODIFY item VARCHAR(20),
MODIFY quantity INT,
MODIFY price_per_unit DECIMAL(10,2),
MODIFY total_spent DECIMAL(10,2),
MODIFY payment_method VARCHAR(20),
MODIFY location VARCHAR(20); -- transaction date didnt convert, i have to fix it then alter the datatype real quick

-- converting date to yyyy-mm-dd ISO 8601 format
SELECT `transaction_date`,
STR_TO_DATE(`transaction_date`, '%m/%d/%Y')
FROM staging_cafe_sales
WHERE transaction_date <> 'Unknown';

UPDATE staging_cafe_sales
SET transaction_date = STR_TO_DATE(`transaction_date`, '%m/%d/%Y')
WHERE transaction_date <> 'Unknown';

SELECT * FROM staging_cafe_sales ORDER BY 5 DESC;
-- gotta convert Unknown dates to null so powerbi doesnt break
UPDATE staging_cafe_sales
SET transaction_date = NULL 
WHERE transaction_date <> 'Unknown';

ALTER TABLE staging_cafe_sales
MODIFY transaction_date DATE;
DESCRIBE staging_cafe_sales;

-- will standardized further
ALTER TABLE staging_cafe_sales ADD PRIMARY KEY (transaction_id);
UPDATE staging_cafe_sales
SET transaction_date = '1900-01-01'
WHERE transaction_date IS NULL;

UPDATE staging_cafe_sales
SET item = 'Unspecified'
WHERE item IS NULL;

UPDATE staging_cafe_sales
SET item = 'Unknown' 
WHERE item = 'Unspecified';

CREATE INDEX idx_date ON staging_cafe_sales(transaction_date);
CREATE INDEX idx_item ON staging_cafe_sales(item);
SHOW INDEXES FROM staging_cafe_sales;
DESCRIBE staging_cafe_sales;

-- JUNE 18 2025
-- EXPLORATORY DATA ANALYSIS 
SELECT *
FROM staging_cafe_sales
ORDER BY 2;
-- will make questions about my table so i can do eda then data viz
-- what item is the most sold, how many items were sold in 2023?, total revenue?, what months a specific item is most sold or day of the week, how about seasons, quarters?
-- most used payment method and way of purchased?
-- just playing around while learning what is eda

SELECT COUNT(*)-COUNT(quantity),  COUNT(*)-COUNT(price_per_unit),  COUNT(*)-COUNT(total_spent)
FROM staging_cafe_sales; -- checking total nulls = 70 NULLS

SELECT COUNT(*)
FROM staging_cafe_sales
WHERE item = 'Unspecified' OR payment_method = 'Unknown' OR transaction_date = '1900-01-01'; -- 3793, so total of 3863 out of 10000 unspecified and null values, more than a third of the total
   
SELECT MIN(transaction_date), MAX(transaction_date)
FROM staging_cafe_sales
WHERE transaction_date <>'1900-01-01'; -- showed that the data is for the whole 2023 year

SELECT SUM(quantity), SUM(total_spent)
FROM staging_cafe_sales; -- total number of sales is 30180, total spent is 89005

SELECT item, SUM(total_spent) total
FROM staging_cafe_sales
GROUP BY item
ORDER BY 2 DESC; -- SALAD SEEMS TO BE THE MOST SOLD ITEM

SELECT * FROM staging_cafe_sales
WHERE transaction_date = '1900-01-01';

SELECT transaction_date, SUM(TOTAL_SPENT)
FROM staging_cafe_sales
WHERE transaction_date <> '1900-01-01'
GROUP BY transaction_date
ORDER BY 2 DESC; -- found out that july 24 is the most sales during 2023

SELECT MONTHNAME(transaction_date) month, SUM(total_spent) total_per_month
FROM staging_cafe_sales
WHERE transaction_date <> '1900-01-01'
GROUP BY month
ORDER BY 2 DESC; -- appears that the month of june is the most sales in 2023 with 7353 followed by october and january without including dates that has no records

SELECT * FROM staging_cafe_sales;
-- im trying to find the average of the total per item and see what item/s is more than that average
WITH total_item AS (
		 SELECT item, SUM(total_spent) total_sold
		 FROM staging_cafe_sales
		 GROUP BY item),
     avg_item AS (
		 SELECT AVG(total_sold) avg_sold
		 FROM total_item)

SELECT item, total_sold
FROM total_item t, avg_item a
WHERE total_sold > avg_sold
ORDER BY 2 DESC
LIMIT 3; -- so salad, sandwich, smoothie are the big guns
-- after this i asked gpt to give me questions then i will figure out the query for it focused in eda, tho i think im pretty much ready for data viz will just play a bit
-- Find the top 3 items with the highest total revenue per payment_method
WITH total_rev_per_paymethod AS (
			SELECT item, payment_method, SUM(total_spent) total
			FROM staging_cafe_sales
			WHERE item <> 'Unknown' AND payment_method <> 'Unknown'
			GROUP BY item, payment_method
			ORDER BY 3 DESC), 
        ranked_item AS (
			SELECT item, payment_method, total, DENSE_RANK() OVER(PARTITION BY payment_method ORDER BY total DESC) rnk
			FROM total_rev_per_paymethod)
SELECT *
FROM ranked_item
WHERE rnk <= 3; -- Salad, Sandwich, and Smoothie are the top-performing items for Cash, Credit Card, and Digital Wallet payments respectively


SELECT * FROM staging_cafe_sales;
UPDATE staging_cafe_sales
SET transaction_date = NULL
WHERE transaction_date = '1900-01-01';

SHOW TABLES;
DROP TABLE backup_table1;

SELECT * FROM cafe_sales;
TRUNCATE cafe_sales;
INSERT INTO cafe_sales
SELECT * FROM staging_cafe_sales;
DESCRIBE cafe_sales;
DESCRIBE staging_cafe_sales; -- so inserting doesnt not copy data types and primary keys and indexes so will just create a new table with other name or maybe just rename this staging and create a backup

CREATE TABLE backup_cafe_sales LIKE staging_cafe_sales;
INSERT INTO backup_cafe_sales 
SELECT * FROM staging_cafe_sales;

SELECT * FROM backup_cafe_sales;
DESCRIBE backup_cafe_sales;
DROP TABLE cafe_sales;
RENAME TABLE staging_cafe_sales TO cafe_sales;
SHOW TABLES;
SELECT * FROM cafe_sales;	

SELECT SUM(total_spent)
FROM cafe_sales
WHERE item = 'Unspecified'; -- 83864

SELECT COUNT(DISTINCT(transaction_id))
FROM cafe_sales
WHERE item <> 'Unspecified'; -- 9520

SELECT SUM(quantity)
FROM cafe_sales
WHERE item <> 'Unspecified'; -- 28709

SELECT SUM(total_spent)/COUNT(DISTINCT(transaction_id))
FROM cafe_sales
WHERE item <> 'Unspecified'; -- 8.809244

SELECT SUM(total_spent)/SUM(quantity)
FROM cafe_sales
WHERE item <> 'Unspecified'; -- 2.921175

SELECT item,
	   CASE 
		 WHEN quantity = 1 THEN 'Single'
		 WHEN quantity IN (2, 3) THEN 'Small'
         WHEN quantity IN (4, 5) THEN 'Large'
         ELSE NULL 
         END AS 'order_size',
         COUNT(*) order_count
FROM cafe_sales
WHERE item <> 'Unspecified' AND quantity BETWEEN 1 AND 5 AND quantity IN (4, 5)
GROUP BY item, order_size
ORDER BY 3 DESC; -- TOP 5: coffee - 525, salad - 521, cookie, 489, tea, 481, cake - 473. BOTTOM 3: juice - 459, sandwich - 454, smoothie - 451

SELECT item, SUM(total_spent)
FROM cafe_sales
WHERE item <> 'Unspecified'
GROUP BY item
ORDER BY 2 DESC; -- TOP 5: SALAD - 19095, SANDWICH - 13664, SMOOTHIE - 13320, JUICE - 10509, CAKE - 10395. BOTTOM 3: coffee - 7808, tea - 5475, cookie - 3598

SELECT item, SUM(quantity)
FROM cafe_sales
WHERE item <> 'Unspecified'
GROUP BY item
ORDER BY 2 DESC; -- TOP 5: Coffee – 3904, Salad – 3819, Tea – 3650, Cookie – 3598, Juice – 3505. BOTTOM 3: Cake – 3468, Sandwich – 3429, Smoothie – 3336

SELECT DAYNAME(transaction_date) AS 'order day', COUNT(DISTINCT(transaction_id)) AS 'total orders'
FROM cafe_sales
WHERE item <> 'Unspecified' AND transaction_date IS NOT NULL
GROUP BY DAYNAME(transaction_date)
ORDER BY 2 DESC; -- FRIDAY; 1331, SUNDAY; 1323, THURSDAY;1315, MONDAY;1312, SATURDAY;1289, WEDNESDAY;1264, TUESDAY;1250

SELECT MONTHNAME(transaction_date) AS 'order day', COUNT(DISTINCT(transaction_id)) AS 'total orders'
FROM cafe_sales
WHERE item <> 'Unspecified' AND transaction_date IS NOT NULL
GROUP BY MONTHNAME(transaction_date)
ORDER BY 2 DESC; -- OCT; 806, MAR; 796, JAN; 786, JUN; 773, JUL; 762, NOV; 754, AUG; 753, SEP; 748, DEC; 744, MAY; 739, APR; 736, FEB; 687

SELECT location, (SUM(total_spent)*100)/(SELECT SUM(total_spent) FROM cafe_sales WHERE location <> 'Unknown' AND item <> 'Unspecified') AS '% of Sales'
FROM cafe_sales
WHERE location <> 'Unknown' AND item <> 'Unspecified'
GROUP BY location
ORDER BY 2 DESC; -- instore;50.834035, takeaway;49.165965

SELECT payment_method, (SUM(total_spent)*100)/(SELECT SUM(total_spent) FROM cafe_sales WHERE payment_method <> 'Unknown' AND item <> 'Unspecified') AS '% of Sales'
FROM cafe_sales
WHERE payment_method <> 'Unknown' AND item <> 'Unspecified'
GROUP BY payment_method
ORDER BY 2 DESC; -- CASH; 33.437925, CREDITCARD;33.326110, DIGIWALLET; 33.235965

SELECT CASE
			 WHEN item IN ('Tea', 'Smoothie', 'Juice', 'Coffee') THEN 'Drinks'
			 WHEN item IN ('Salad','Sandwich') THEN 'Food'
			 WHEN item IN ('Cake', 'Cookie') THEN 'Desserts'
			 END AS item_category,
             SUM(total_spent) AS total_revenue,
             (SELECT SUM(total_spent) FROM cafe_sales WHERE item <> 'Unspecified') AS overall_total
FROM cafe_sales
WHERE item <> 'Unspecified'
GROUP BY CASE
			 WHEN item IN ('Tea', 'Smoothie', 'Juice', 'Coffee') THEN 'Drinks'
			 WHEN item IN ('Salad','Sandwich') THEN 'Food'
			 WHEN item IN ('Cake', 'Cookie') THEN 'Desserts'
			 END; -- DRINKS;37112, FOOD;32759, DESSERTS;13993
