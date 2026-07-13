# Import required libraries
import pandas as pd

from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier

from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix
)

import joblib


# Load the sensor dataset
df = pd.read_csv("data/raw/MachineSensorData.csv")

# Display basic information
print("First 5 Rows:")
print(df.head())

print("\nDataset Shape:")
print(df.shape)

print("\nColumn Names:")
print(df.columns)

print("\nMissing Values:")
print(df.isnull().sum())



# Select features (X) and target variable (y)

X = df[['Temperature',
        'Vibration',
        'Pressure',
        'RPM',
        'PowerConsumptionKW']]

y = df['IsAnomaly']

print("\nFeature Matrix Shape:", X.shape)
print("Target Vector Shape:", y.shape)

print("\nFirst 5 Feature Rows:")
print(X.head())

print("\nTarget Distribution:")
print(y.value_counts())

# Split the dataset into training and testing sets

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.20,
    random_state=42,
    stratify=y
)

print("\nTraining Feature Shape:", X_train.shape)
print("Testing Feature Shape:", X_test.shape)

print("\nTraining Target Shape:", y_train.shape)
print("Testing Target Shape:", y_test.shape)

# Train the Random Forest Classifier

# Train the Random Forest Classifier

model = RandomForestClassifier(
    n_estimators=100,
    random_state=42
)

model.fit(X_train, y_train)

print("\nRandom Forest model trained successfully!")

# Make predictions on the test data

y_pred = model.predict(X_test)

print("\nPredictions generated successfully!")

# Evaluate model performance

print("\nModel Accuracy:")
print(accuracy_score(y_test, y_pred))

print("\nClassification Report:")
print(classification_report(y_test, y_pred))

print("\nConfusion Matrix:")
print(confusion_matrix(y_test, y_pred))


print("\nFeature Statistics:")
print(df.describe())

print("\nCorrelation with IsAnomaly:")
print(df.corr(numeric_only=True)["IsAnomaly"])


# Save the trained model

joblib.dump(model, "models/random_forest_model.pkl")

print("\nModel saved successfully!")