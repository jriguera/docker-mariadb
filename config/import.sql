-- Create a new database
-- This file will not be imported because the DB already exists. The failure does not abort the startup process
CREATE DATABASE one;

-- Use the database
USE one;

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
