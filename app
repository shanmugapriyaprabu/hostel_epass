from flask import Flask, render_template, request, redirect, url_for, session
import sqlite3
from datetime import datetime
import pandas as pd
from flask import send_file
import io
from werkzeug.utils import secure_filename
import os


app = Flask(__name__)

@app.route('/')
def home():
    return render_template('home.html')  # Make sure home.html exists

if __name__ == '__main__':
    app.run()



conn = sqlite3.connect('epass.db')
c = conn.cursor()
c.execute("SELECT * FROM epass")
rows = c.fetchall()
print(rows)

def format_date(date_str):
    if date_str:
        return datetime.strptime(date_str, '%Y-%m-%d').strftime('%d-%m-%Y')
    return ''
apps = []
for row in rows:
    row = list(row)
    row[8] = format_date(row[8])  # outing_date
    row[9] = format_date(row[9])  # leave_from
    row[10] = format_date(row[10])  # leave_to
    apps.append(row)

# Add each column only if not already present
try: c.execute("ALTER TABLE epass ADD COLUMN category TEXT")
except: pass
try: c.execute("ALTER TABLE epass ADD COLUMN outing_date TEXT")
except: pass
try: c.execute("ALTER TABLE epass ADD COLUMN outing_time TEXT")
except: pass
try: c.execute("ALTER TABLE epass ADD COLUMN leave_from TEXT")
except: pass
try: c.execute("ALTER TABLE epass ADD COLUMN leave_to TEXT")
except: pass
try: c.execute("ALTER TABLE epass ADD COLUMN leave_days TEXT")
except: pass

conn.commit()
conn.close()



app = Flask(__name__)
app.secret_key = 'mahendra_secret'

# Connect to SQLite DB
db = sqlite3.connect('epass.db', check_same_thread=False)
c = db.cursor()


# ---------- DATABASE SETUP ----------
# Create tables if not exist
c.execute('''
    CREATE TABLE IF NOT EXISTS students (
        reg_no TEXT PRIMARY KEY,
        name TEXT,
        department TEXT,
        year TEXT,
        section TEXT,
        email TEXT,
        student_mobile TEXT,
        parent_mobile TEXT,
        password TEXT
    )
''')

# Create epass table if not exist
c.execute('''
    CREATE TABLE IF NOT EXISTS epass (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reg_no TEXT,
        name TEXT,
        year TEXT,
        department TEXT,
        room_no TEXT,
        category TEXT,
        date TEXT,
        date_from TEXT,
        date_to TEXT,
        time TEXT,
        reason TEXT,
        status TEXT DEFAULT 'Pending'
    )
''')

# Schema migration - add missing columns if needed
columns_to_add = [
    ("category", "TEXT"),
    ("date", "TEXT"),
    ("date_from", "TEXT"),
    ("date_to", "TEXT"),
    ("time", "TEXT")
]
for col, col_type in columns_to_add:
    try:
        c.execute(f"ALTER TABLE epass ADD COLUMN {col} {col_type}")
    except sqlite3.OperationalError:
        pass  # Column already exists

db.commit()

# ---------- ROUTES ----------

@app.route('/')
def home():
    if 'admin_logged_in' in session:
        return redirect(url_for('admin_dashboard'))
    elif 'reg_no' in session:
        return redirect(url_for('student_dashboard'))
    return render_template('home.html')



# ----------- ADMIN MODULE -----------

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
    apps = c.fetchall()
    return render_template('admin_dashboard.html', apps=apps)


@app.route('/admin/approve/<int:appid>')
def approve(appid):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    c.execute("UPDATE epass SET status='Approved' WHERE id=?", (appid,))
    db.commit()
    return redirect(url_for('admin_dashboard'))

@app.route('/admin/reject/<int:appid>')
def reject(appid):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    c.execute("UPDATE epass SET status='Rejected' WHERE id=?", (appid,))
    db.commit()
    return redirect(url_for('admin_dashboard'))


@app.route('/admin/add_student', methods=['GET', 'POST'])
def add_student():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    msg = None
    if request.method == 'POST':
        data = (
            request.form['reg_no'], request.form['name'], request.form['department'],
            request.form['year'], request.form['section'], request.form['email'],
            request.form['student_mobile'], request.form['parent_mobile'], request.form['password']
        )
        c.execute("INSERT OR REPLACE INTO students VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", data)
        db.commit()
        msg = 'Student added/updated successfully.'
    return render_template('add_student.html', msg=msg)

@app.route('/admin/edit_student/<reg_no>', methods=['GET', 'POST'])
def edit_student(reg_no):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    if request.method == 'POST':
        updated = (
            request.form['name'], request.form['department'], request.form['year'],
            request.form['section'], request.form['email'], request.form['student_mobile'],
            request.form['parent_mobile'], reg_no
        )
        c.execute("""
            UPDATE students SET name=?, department=?, year=?, section=?, email=?,
            student_mobile=?, parent_mobile=? WHERE reg_no=?
        """, updated)
        db.commit()
        return redirect(url_for('admin_dashboard'))

    c.execute("SELECT * FROM students WHERE reg_no=?", (reg_no,))
    row = c.fetchone()
    student = {
        'reg_no': row[0], 'name': row[1], 'department': row[2], 'year': row[3],
        'section': row[4], 'email': row[5], 'student_mobile': row[6], 'parent_mobile': row[7]
    }
    return render_template('edit_student.html', student=student)


# ----------- STUDENT MODULE -----------

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



# ----------- ePASS APPLY -----------
@app.route('/student/apply_epass', methods=['GET', 'POST'])
def apply_epass():
    if 'reg_no' not in session:
        return redirect(url_for('student_login'))

    reg_no = session['reg_no']
    c.execute("SELECT name, year, department FROM students WHERE reg_no=?", (reg_no,))
    student = c.fetchone()

    if request.method == 'POST':
        name, year, department = student
        room_no = request.form['room_no']
        category = request.form['leave_type']
        reason = request.form['reason']

        # Defaults
        outing_date = outing_time = leave_from = leave_to = leave_days = None

        if category == 'Outing':
            outing_date = request.form.get('outing_date')
            outing_time = request.form.get('outing_time')
        elif category == 'Leave':
            leave_from = request.form.get('leave_from')
            leave_to = request.form.get('leave_to')
            leave_days = request.form.get('leave_days')

        # Insert into epass table
        c.execute('''
            INSERT INTO epass 
            (reg_no, name, year, department, room_no, reason, category, 
             outing_date, outing_time, leave_from, leave_to, leave_days, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            reg_no, name, year, department, room_no, reason, category,
            outing_date, outing_time, leave_from, leave_to, leave_days, 'Pending'
        ))
        db.commit()

        return redirect(url_for('student_dashboard'))

    return render_template('apply_epass.html')

@app.route('/admin/students')
def students_list():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    page = request.args.get('page', 1, type=int)
    per_page = 20
    offset = (page - 1) * per_page

    department = request.args.get('department', '')
    year = request.args.get('year', '')

    query = "SELECT * FROM students WHERE 1=1"
    params = []

    if department:
        query += " AND department = ?"
        params.append(department)
    if year:
        query += " AND year = ?"
        params.append(year)

    total_query = "SELECT COUNT(*) FROM (" + query + ")"
    c.execute(total_query, params)
    total = c.fetchone()[0]
    total_pages = (total + per_page - 1) // per_page

    query += " LIMIT ? OFFSET ?"
    params.extend([per_page, offset])
    c.execute(query, params)
    students = c.fetchall()

    # Get unique departments and years for filter dropdowns
    c.execute("SELECT DISTINCT department FROM students")
    departments = [row[0] for row in c.fetchall()]
    c.execute("SELECT DISTINCT year FROM students")
    years = [row[0] for row in c.fetchall()]

    return render_template('students_list.html',
                           students=students,
                           page=page,
                           total_pages=total_pages,
                           departments=departments,
                           years=years,
                           selected_dept=department,
                           selected_year=year)



@app.route('/student/status')
def check_status():
    if 'reg_no' not in session:
        return redirect(url_for('student_login'))
    reg_no = session['reg_no']
    c.execute("SELECT * FROM epass WHERE reg_no=? ORDER BY id DESC", (reg_no,))
    apps = c.fetchall()
    return render_template('status.html', apps=apps)

@app.route('/admin/delete_student/<reg_no>', methods=['GET', 'POST'])
def delete_student(reg_no):
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))
    c.execute("DELETE FROM students WHERE reg_no=?", (reg_no,))
    db.commit()
    return redirect(url_for('students_list'))


@app.route('/admin/export_students')
def export_students():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    c.execute("SELECT * FROM students")
    students = c.fetchall()
    df = pd.DataFrame(students, columns=['Reg No', 'Name', 'Department', 'Year', 'Section', 'Email', 'Student Mobile', 'Parent Mobile', 'Password'])
    df.drop(columns='Password', inplace=True)

    file_path = 'students_export.xlsx'
    df.to_excel(file_path, index=False)

    return send_file(file_path, as_attachment=True)


UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'xlsx'}

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/admin/upload_excel', methods=['GET', 'POST'])
def upload_excel():
    if 'admin_logged_in' not in session:
        return redirect(url_for('admin_login'))

    msg = ''
    if request.method == 'POST':
        file = request.files['excel_file']
        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(filepath)

            # Read Excel and insert into database
            df = pd.read_excel(filepath)

            for _, row in df.iterrows():
                try:
                    c.execute("""
                        INSERT INTO students (reg_no, name, department, year, section, email, student_mobile, parent_mobile, password)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        row['Register Number'], row['Name'], row['Department'], row['Year'],
                        row['Section'], row['Email'], row['Student Mobile'],
                        row['Parent Mobile'], row['Password']
                    ))
                except sqlite3.IntegrityError:
                    continue  # Skip duplicates

            db.commit()
            msg = 'Students added successfully!'
        else:
            msg = 'Invalid file format. Please upload .xlsx only.'

    return render_template('upload_excel.html', msg=msg)

# ---------- MAIN ----------
if __name__ == '__main__':
    app.run(debug=True)
