-- DB is already created!
-- As opposite to the other file (up folder), in this file a failure means the startup process will stop
-- CREATE DATABASE two;

-- Use the database
USE two;

-- Create a table
CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    age INT,
    salary DECIMAL(10, 2)
);

-- Insert data into the table
INSERT INTO employees (id, name, age, salary) VALUES
    (1, 'John Doe', 30, 5000.00),
    (2, 'Jane Smith', 35, 6000.00),
    (3, 'Mike Johnson', 28, 4500.00);

-- Select data from the table
SELECT * FROM employees;
