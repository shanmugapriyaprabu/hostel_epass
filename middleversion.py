# app.py
from flask import Flask, render_template, request, redirect, url_for, session
import sqlite3
import datetime
import pandas as pd
from flask import send_file
import io



app = Flask(__name__)
app.secret_key = 'mahendra_secret'
db = sqlite3.connect('epass.db', check_same_thread=False)
c = db.cursor()

# Create tables if they don't exist
c.execute('''CREATE TABLE IF NOT EXISTS students (
    reg_no TEXT PRIMARY KEY,
    name TEXT,
    department TEXT,
    year TEXT,
    section TEXT,
    email TEXT,
    student_mobile TEXT,
    parent_mobile TEXT,
    password TEXT
)''')
c.execute('''CREATE TABLE IF NOT EXISTS epass (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    reg_no TEXT,
    name TEXT,
    year TEXT,
    department TEXT,
    room_no TEXT,
    reason TEXT,
    date TEXT,
    time TEXT,
    status TEXT DEFAULT 'Pending'
)''')
db.commit()

# Home Page
@app.route('/')
def home():
    return render_template('home.html')

# Admin Login
@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    error = None
    if request.method == 'POST':
        if request.form['username'] == 'admin' and request.form['password'] == 'admin':
            session['admin_logged_in'] = True
            return redirect(url_for('admin_dashboard'))
        else:
            error = 'Invalid credentials'
    return render_template('admin_login.html', error=error)

@app.route('/admin/logout')
def admin_logout():
    session.pop('admin_logged_in', None)
    return redirect(url_for('home'))

@app.route('/admin/dashboard')
def admin_dashboard():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    c.execute("SELECT * FROM epass")
    applications = c.fetchall()
    return render_template('admin_dashboard.html', applications=applications)

@app.route('/admin/approve/<int:appid>')
def approve(appid):
    c.execute("UPDATE epass SET status='Approved' WHERE id=?", (appid,))
    db.commit()
    return redirect(url_for('admin_dashboard'))

@app.route('/admin/reject/<int:appid>')
def reject(appid):
    c.execute("UPDATE epass SET status='Rejected' WHERE id=?", (appid,))
    db.commit()
    return redirect(url_for('admin_dashboard'))

@app.route('/admin/add_student', methods=['GET', 'POST'])
def add_student():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    msg = None
    if request.method == 'POST':
        data = (request.form['reg_no'], request.form['name'], request.form['department'],
                request.form['year'], request.form['section'], request.form['email'],
                request.form['student_mobile'], request.form['parent_mobile'], request.form['password'])
        c.execute("INSERT INTO students VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", data)
        db.commit()
        msg = 'Student added successfully.'
    return render_template('add_student.html', msg=msg)


@app.route('/admin/edit_student/<reg_no>', methods=['GET', 'POST'])
def edit_student(reg_no):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    if request.method == 'POST':
        updated = (request.form['name'], request.form['department'], request.form['year'],
                   request.form['section'], request.form['email'], request.form['student_mobile'],
                   request.form['parent_mobile'], reg_no)
        c.execute("""
            UPDATE students SET name=?, department=?, year=?, section=?,
            email=?, student_mobile=?, parent_mobile=? WHERE reg_no=?
        """, updated)
        db.commit()
        return redirect(url_for('students_list'))

    c.execute("SELECT * FROM students WHERE reg_no=?", (reg_no,))
    row = c.fetchone()
    student = {
        'reg_no': row[0], 'name': row[1], 'department': row[2], 'year': row[3],
        'section': row[4], 'email': row[5], 'student_mobile': row[6], 'parent_mobile': row[7]
    }
    return render_template('edit_student.html', student=student)

@app.route('/admin/delete_student/<reg_no>')
def delete_student(reg_no):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    c.execute("DELETE FROM students WHERE reg_no=?", (reg_no,))
    db.commit()
    return redirect(url_for('students_list'))


@app.route('/admin/students', methods=['GET', 'POST'])
def students_list():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    department_filter = request.args.get('department')
    year_filter = request.args.get('year')

    query = "SELECT * FROM students WHERE 1=1"
    params = []

    if department_filter:
        query += " AND department=?"
        params.append(department_filter)
    if year_filter:
        query += " AND year=?"
        params.append(year_filter)

    c.execute(query, params)
    students = c.fetchall()

    c.execute("SELECT DISTINCT department FROM students")
    departments = [row[0] for row in c.fetchall()]

    c.execute("SELECT DISTINCT year FROM students")
    years = [row[0] for row in c.fetchall()]

    return render_template("students_list.html", students=students, departments=departments, years=years)


@app.route('/admin/export_students')
def export_students():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    c.execute("SELECT reg_no, name, department, year, section, email, student_mobile, parent_mobile FROM students")
    data = c.fetchall()

    columns = ['Reg No', 'Name', 'Department', 'Year', 'Section', 'Email', 'Student Mobile', 'Parent Mobile']
    df = pd.DataFrame(data, columns=columns)

    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Students')

    output.seek(0)
    return send_file(output, as_attachment=True, download_name="students_list.xlsx", mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
# Student Login
@app.route('/student/login', methods=['GET', 'POST'])
def student_login():
    error = None
    if request.method == 'POST':
        reg_no = request.form['reg_no']
        password = request.form['password']
        c.execute("SELECT * FROM students WHERE reg_no=? AND password=?", (reg_no, password))
        student = c.fetchone()
        if student:
            session['reg_no'] = reg_no
            return redirect(url_for('student_dashboard'))
        else:
            error = 'Invalid credentials'
    return render_template('student_login.html', error=error)

@app.route('/student/logout')
def student_logout():
    session.pop('reg_no', None)
    return redirect(url_for('home'))

@app.route('/student/dashboard')
def student_dashboard():
    if 'reg_no' not in session:
        return redirect(url_for('student_login'))
    reg_no = session['reg_no']
    c.execute("SELECT * FROM students WHERE reg_no=?", (reg_no,))
    row = c.fetchone()
    student = {
        'reg_no': row[0], 'name': row[1], 'department': row[2], 'year': row[3],
        'section': row[4], 'email': row[5], 'student_mobile': row[6], 'parent_mobile': row[7]
    }
    return render_template('student_dashboard.html', student=student)

@app.route('/apply_epass', methods=['GET', 'POST'])
def apply_epass():
    if 'reg_no' not in session:
        return redirect(url_for('student_login'))
    if request.method == 'POST':
        reg_no = session['reg_no']
        c.execute("SELECT name, year, department FROM students WHERE reg_no=?", (reg_no,))
        student = c.fetchone()
        name, year, department = student
        date = request.form['date']
        time = request.form['time']
        reason = request.form['reason']
        room_no = request.form.get('room_no', '-')
        c.execute("INSERT INTO epass (reg_no, name, year, department, room_no, reason, date, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                  (reg_no, name, year, department, room_no, reason, date, time))
        db.commit()
        return redirect(url_for('student_dashboard'))
    return render_template('apply_epass.html')

@app.route('/student/status')
def check_status():
    if 'reg_no' not in session:
        return redirect(url_for('student_login'))
    reg_no = session['reg_no']
    c.execute("SELECT * FROM epass WHERE reg_no=?", (reg_no,))
    apps = c.fetchall()
    return render_template('status.html', apps=apps)

if __name__ == '__main__':
    app.run(debug=True)
