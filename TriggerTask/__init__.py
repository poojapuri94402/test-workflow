import os, string, random
from azure.storage.blob import BlobServiceClient
import azure.functions as func
import pandas as pd
from io import StringIO, BytesIO
from validate_email import validate_email

def main(myblob: func.InputStream):
    source_conn_string = os.environ["blobstorageaccountsource_STORAGE"]
    dest_conn_string = os.environ["blobstorageaccountdestination_STORAGE"]
    source_container_name="demo-data"
    destination_container_name="demo-data"
    try:
        blob_service_client=BlobServiceClient.from_connection_string(source_conn_string)
        #Fetch employee data blob details
        employee_blob_client = blob_service_client.get_blob_client(container = source_container_name, blob = "employee-data.csv")
        employee_blob = employee_blob_client.download_blob().readall().decode('ascii', 'ignore')
        employee_df = pd.read_csv(StringIO(employee_blob))
        print(employee_df)
        #Fetch department data blob details
        department_blob_client = blob_service_client.get_blob_client(container = source_container_name, blob = "department-data.csv")
        department_blob = department_blob_client.download_blob().readall().decode('ascii', 'ignore')
        department_df = pd.read_csv(StringIO(department_blob))
        print(department_df)
        #Validating the csv files - schema validation + Null + Incorrect format data
        if validate_files(employee_df, department_df):
            #Joining df from two csvs
            df = pd.merge(employee_df, department_df, left_on="DEPARTMENT_ID", right_on="DEPARTMENT_ID")
            parquet_file = BytesIO()
            df.to_parquet(parquet_file, engine = 'pyarrow')
            parquet_file.seek(0)
            #Creating parquet file and deploying to destination storage account
            res = ''.join(random.choices(string.ascii_uppercase +string.digits, k=7))
            blob_path = 'new-data/merged{}.parquet'.format(str(res))
            dest_blob_service_client = BlobServiceClient.from_connection_string(dest_conn_string)
            blob_client = dest_blob_service_client.get_blob_client(container = destination_container_name, blob = blob_path)
            blob_client.upload_blob(data = parquet_file, overwrite=False)
        else:
            raise Exception("Files are invalid")
    except Exception as e:
        return str(e)
    return "Executed Successfully."

def validate_files(employee_df, department_df):
    error_msgs = {
        "employee_empty_cell":"Employee file contains empty cells",
        "department_empty_cell":"Department file contains empty cells",
        "invalid_email":"One/Multiple email id(s) are wrong in employee data",
        "invalid_phone_number":"One/Multiple phone number(s) are wrong in employee data"
    }
    if employee_df.isnull().values.any():
        raise Exception(error_msgs.get("employee_empty_cell"))
    if department_df.isnull().values.any():
        raise Exception(error_msgs.get("department_empty_cell"))
    employee_df['is_valid_email'] = employee_df['EMAIL'].apply(lambda x:validate_email(x))
    if not employee_df['is_valid_email'].all():
        raise Exception(error_msgs.get("invalid_email"))
    # try:
    #     employee_df['phone_valid'] = employee_df.apply(lambda x: phonenumbers.is_valid_number(phonenumbers.parse("+"+str(x.PHONE_NUMBER), None)), axis=1)
    #     if not employee_df['phone_valid'].all():
    #         raise Exception(error_msgs.get("invalid_phone_number"))
    # except Exception as e:
    #     raise Exception(error_msgs.get("invalid_phone_number"))
    return True