from flask import Flask, request, jsonify
import mysql.connector

import base64
import json
from openai import OpenAI
import sys

import ifcopenshell

client = OpenAI(api_key="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")

def get_room_id(rooms, audio_file_path):
    system_prompt = "You are a helpful assistant for maintenance stuff, maintenance stuff have already get some information of devices which are in json format. And maintenance stuff are going to give some additional information about the devices, you need to compare the additional information with the rooms information of this building. If the additional information provides location information, try to match the most possible room. Your output should only conteain the matched room's global_id, if no match, output NO_MATCH"
    response = client.chat.completions.create(
        model="gpt-4o",
        temperature=0,
        messages=[
            {
                "role": "system",
                "content": system_prompt
            },
            {
                "role": "user",
                "content": f"room files: {json.loads(rooms)}, additional information: {transcribe(audio_file_path)}"
            }
        ]
    )
    
    room_id = response.choices[0].message.content
    return room_id

# 生成新的 GlobalId
from ifcopenshell import guid

def creat_equipment(ifc_file, json_file):
    equipment_guid = guid.new()

    # 创建设备实体
    equipment = ifc_file.create_entity(
        'IfcEquipmentElement',
        GlobalId=equipment_guid,
        # *(json.loads(json_file))
        **json_file
    )
    return equipment

def create_contain(ifc_file, target_room, equipment):
    # 创建包含关系
    rel_contained = ifc_file.create_entity(
        'IfcRelContainedInSpatialStructure',
        GlobalId=guid.new(),
        OwnerHistory=ifc_file.by_type('IfcOwnerHistory')[0],
        RelatingStructure=target_room,
        RelatedElements=[equipment]
    )
    return rel_contained



def image2json(base64_image):
  size = sys.getsizeof(base64_image)
  print(f"对象占用内存大小: {size} 字节")
  # Getting the base64 string
  response = client.chat.completions.create(
    temperature=0, 
    model="gpt-4o-mini",
    messages=[
      {
        "role": "system",
        "content": "you are going to help user summarize forms from the picture into json files, the your answer should contain only the json files. The file should contain the following information: equipment name, location in the building, manufacturer, model, serial number, equipment type (e.g. structure, ventilation, electrical), size, age, type of material, condition as well as surveyor's free comments. if you can't find these information, set them to null"

      }
      ,{
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url":  f"data:image/jpeg;base64,{base64_image}"
            },
          },
        ],
      }
    ],
  )

  data = response.choices[0].message.content
  data = data.replace('```json\n', '').rstrip('```')
  data = json.dumps(data, ensure_ascii=False, indent=4)

  return data


def transcribe(base64_audio):
    audio_data = base64.b64decode(base64_audio)
    # print("audio_file")
    with open("temp_audio.mp3", "wb") as audio_file:
        audio_file.write(audio_data)
    with open("temp_audio.mp3", "rb") as audio_file:
        transcription = client.audio.transcriptions.create(
        model="whisper-1", 
        file=audio_file
        )
    print(transcription.text)
    return transcription.text

def voice_modify_json(json_file, audio_file_path):
    system_prompt = "You are a helpful assistant for maintenance stuff, maintenance stuff have already get some information of devices which are in json format. And maintenance stuff are going to give some additional information about the devices, you need to add their additional information to the json files. The information from voice has to be labled as (from voice). And output updated json file only"
    response = client.chat.completions.create(
        model="gpt-4o",
        temperature=0,
        messages=[
            {
                "role": "system",
                "content": system_prompt
            },
            {
                "role": "user",
                "content": f"json files: {json.loads(json_file)}, additional information: {transcribe(audio_file_path)}"
            }
        ]
    )
    data = response.choices[0].message.content
    data = data.replace('```json\n', '').rstrip('```')
    data = json.dumps(data, ensure_ascii=False, indent=4)
    return data




# 读取 IFC 文件
def modify_ifc(ifc_file_path, voice_data, json_data):
    ifc_file = ifcopenshell.open(ifc_file_path)

    spaces = ifc_file.by_type('IfcSpace')

    # 遍历所有房间并打印信息
    rooms = {}
    for space in spaces:    
        if space.GlobalId not in rooms:
            rooms[space.GlobalId] = {}
        rooms[space.GlobalId]["name"] = space.Name
        rooms[space.GlobalId]["long_name"] = space.LongName
        rooms[space.GlobalId]["description"] = space.Description
        
    rooms = json.dumps(rooms)

    room_id = get_room_id(rooms=rooms, audio_file_path=voice_data)
    if room_id != "NO_MATCH":
        target_room = ifc_file.by_guid(room_id)
        equipment = creat_equipment(ifc_file, json_data)
        rel_contained = create_contain(ifc_file, target_room, equipment)

        # Instead of rebuilding inverses or accessing ContainsElements,
        # verify the relationship by querying the relevant relationships
        contained_elements = []
        for rel in ifc_file.by_type('IfcRelContainedInSpatialStructure'):
            if rel.RelatingStructure == target_room:
                contained_elements.extend(rel.RelatedElements)

        # Check if your equipment is in the contained elements
        if equipment in contained_elements:
            print("Equipment successfully associated with the room.")
        else:
            print("Equipment not associated with the room.")

        # Save the modified IFC file
        ifc_file.write('/mnt/c/Users/33196/Desktop/modified_file.ifc')
    else:
        print("No matching room found.")


app = Flask(__name__)

db_config = {
    'host': '35.228.135.177',
    'user': 'your_user',
    'password': 'your_password',
    'database': 'your_database_name'
}

def get_db_connection():
    return mysql.connector.connect(**db_config)

@app.route('/hello', methods=['POST'])
def hello():
    return "hello"

# 添加设备
@app.route('/devices', methods=['POST'])
def add_device():
    data = request.get_json()
    id = data.get('id')
    picture = data.get('picture')
    
    voice = data.get('voice', None)
    location = data.get('location', None)
    
    json_file = image2json(picture)
    if voice is not None:
        json_file = voice_modify_json(json_file, voice)

    if not id or not picture:
        return jsonify({'error': 'Missing id or picture'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        json_file_str = json.dumps(json_file, ensure_ascii=False)
        cursor.execute(
            "INSERT INTO devices (id, picture, voice, location, json_file) VALUES (%s, %s, %s, %s, %s)",
            (id, picture, voice or '', location or '', json_file or '')
        )
        conn.commit()
        return jsonify({'message': 'Device added successfully'}), 201
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return jsonify({'error': 'Failed to insert data'}), 500
    finally:
        cursor.close()
        conn.close()
        print("close")
        try:
            print("if_ voice")
            if voice is not None:
                modify_ifc("/mnt/c/Users/33196/Desktop/Kaapelitehdas_junction.ifc", voice, json_file)
        except Exception as e:
            print(f"Error modifying IFC: {e}")
# 获取所有设备
@app.route('/devices', methods=['GET'])
def get_devices():
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM devices")
        devices = cursor.fetchall()
        
        # 将 bytes 类型的字段转换为字符串
        for device in devices:
            for key in device:
                if isinstance(device[key], bytes):
                    # 如果是文本数据，使用 decode
                    try:
                        if key != "json_file":
                            device[key] = device[key].decode('utf-8') 
                    except UnicodeDecodeError:
                        # 如果是二进制数据，使用 Base64 编码
                        device[key] = base64.b64encode(device[key]).decode('utf-8') 
            # 解析 json_file 字段
            if 'json_file' in device and device['json_file']:
                try:
                    device['json_file'] = json.loads(device['json_file'])
                except json.JSONDecodeError:
                    device['json_file'] = None  # 或者其他默认值
        return jsonify(devices), 200
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return jsonify({'error': 'Failed to fetch data'}), 500
    finally:
        cursor.close()
        conn.close()

# 获取特定设备
@app.route('/devices/<string:id>', methods=['GET'])
def get_device(id):
    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM devices WHERE id = %s", (id,))
        device = cursor.fetchone()
        for key in device:
            if isinstance(device[key], bytes):
                # 如果是文本数据，使用 decode
                try:
                    device[key] = device[key].decode('utf-8')
                except UnicodeDecodeError:
                    # 如果是二进制数据，使用 Base64 编码
                    device[key] = base64.b64encode(device[key]).decode('utf-8') 
        # 解析 json_file 字段
        if 'json_file' in device and device['json_file']:
            try:
                device['json_file'] = json.loads(device['json_file'])
            except json.JSONDecodeError:
                device['json_file'] = None  # 或者其他默认值
                
        # print(device)
        return jsonify(device), 200
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return jsonify({'error': 'Failed to fetch data'}), 500
    finally:
        cursor.close()
        conn.close()

# 更新设备信息
@app.route('/devices/<string:id>', methods=['PUT'])
def update_device(id):
    data = request.get_json()
    picture = data.get('picture')
    
    voice = data.get('voice', None)
    location = data.get('location', None)
    
    json_file = image2json(picture)
    if voice is not None:
        json_file = voice_modify_json(json_file, voice)

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        json_file_str = json.dumps(json_file, ensure_ascii=False)
        cursor.execute(
            "UPDATE devices SET picture=%s, voice=%s, location=%s, json_file=%s WHERE id=%s",
            (picture, voice, location, json_file, id)
        )
        conn.commit()
        return jsonify({'message': 'Device updated successfully'}), 200
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return jsonify({'error': 'Failed to update data'}), 500
    finally:
        cursor.close()
        conn.close()

# 删除设备
@app.route('/devices/<string:id>', methods=['DELETE'])
def delete_device(id):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM devices WHERE id = %s", (id,))
        conn.commit()
        return jsonify({'message': 'Device deleted successfully'}), 200
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return jsonify({'error': 'Failed to delete data'}), 500
    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    app.run(debug=True)

